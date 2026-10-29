#!/usr/bin/env bash
# Run before downloading Python packages/assets: verifies CUDA device injection
# and NVIDIA Vulkan visibility, which nvidia-smi alone cannot establish.
set -euo pipefail

echo '[docker] NVIDIA device / driver'
nvidia-smi

echo '[docker] Vulkan devices'
summary="$(vulkaninfo --summary)"
printf '%s\n' "$summary"
if ! grep -Eiq 'vendorID[[:space:]]*=[[:space:]]*0x10de|deviceName[[:space:]]*=.*NVIDIA' <<< "$summary"; then
    echo 'NVIDIA Vulkan device missing: check NVIDIA Container Toolkit and graphics capability.' >&2
    exit 1
fi

# Actual device enumeration is authoritative: Container Toolkit can inject the
# ICD into /etc/vulkan/icd.d instead of the host's /usr/share location.
echo '[docker] GPU and NVIDIA Vulkan preflight passed; next run the runtime setup steps.'
