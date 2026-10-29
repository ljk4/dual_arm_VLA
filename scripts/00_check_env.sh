#!/usr/bin/env bash
# 本机环境自检：不修改任何东西，只报告。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$ROOT/envs/robotwin/.venv/bin/python"
ROBOTWIN="$ROOT/third_party/RoboTwin"
PASS=0
FAIL=0

ok()   { printf '\033[32m[PASS]\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
bad()  { printf '\033[31m[FAIL]\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
info() { printf '\033[36m[INFO]\033[0m %s\n' "$*"; }

info "repo: $ROOT"

if command -v nvidia-smi >/dev/null 2>&1; then
    gpu="$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader | head -1)"
    ok "GPU: $gpu"
else
    bad "nvidia-smi not found"
fi

if [[ -x "$PY" ]]; then
    ok "uv venv: $PY"
    "$PY" - <<'EOF' && ok "torch + CUDA + sapien import" || bad "torch/sapien import failed"
import torch, sapien
assert torch.cuda.is_available(), "CUDA not available"
print(f"  torch={torch.__version__} cuda={torch.version.cuda} gpu={torch.cuda.get_device_name(0)}")
print(f"  sapien={sapien.__version__}")
EOF
else
    bad "missing uv venv: $PY (run: uv sync --project envs/robotwin)"
fi

if [[ -d "$ROBOTWIN" ]]; then
    ok "RoboTwin: $(git -C "$ROBOTWIN" rev-parse --short HEAD)"
    if [[ -f "$ROBOTWIN/XPolicyLab/pyproject.toml" ]]; then
        ok "XPolicyLab: $(git -C "$ROBOTWIN/XPolicyLab" rev-parse --short HEAD)"
    else
        bad "XPolicyLab submodule missing"
    fi
    for d in objects embodiments; do
        if [[ -d "$ROBOTWIN/assets/$d" ]]; then
            ok "assets/$d present"
        else
            bad "assets/$d missing (run scripts/02_download_assets.sh)"
        fi
    done
else
    bad "RoboTwin checkout missing (run scripts/01_setup_robotwin.sh)"
fi

if [[ -f "$ROOT/envs/robotwin/.cuda_home/bin/nvcc" ]]; then
    ok "CUDA toolkit: $("$ROOT/envs/robotwin/.cuda_home/bin/nvcc" --version | grep release | tail -1)"
else
    bad "project-local CUDA toolkit missing (run scripts/01_setup_robotwin.sh)"
fi

if [[ -x "$PY" ]] && "$PY" -c "import curobo" >/dev/null 2>&1; then
    ok "curobo import"
else
    bad "curobo import failed"
fi

# Vulkan: SAPIEN 需要 libvulkan.so.1 与 NVIDIA ICD
if ldconfig -p 2>/dev/null | grep -q 'libvulkan.so.1'; then
    ok "libvulkan.so.1 present"
else
    bad "libvulkan.so.1 missing (sudo apt install libvulkan1)"
fi
NVIDIA_ICD=''
for icd in /etc/vulkan/icd.d/nvidia_icd*.json /usr/share/vulkan/icd.d/nvidia_icd*.json; do
    if [[ -f "$icd" ]]; then
        NVIDIA_ICD="$icd"
        break
    fi
done
if [[ -n "$NVIDIA_ICD" ]]; then
    ok "NVIDIA Vulkan ICD present: $NVIDIA_ICD"
else
    bad "NVIDIA Vulkan ICD missing"
fi

avail_kb=$(df -Pk "$ROOT" | awk 'NR==2 {print $4}')
if [[ "$avail_kb" -gt 52428800 ]]; then
    ok "disk free: $((avail_kb/1024/1024)) GiB"
else
    bad "disk free: $((avail_kb/1024/1024)) GiB (< 50 GiB)"
fi

echo
if [[ "$FAIL" -eq 0 ]]; then
    printf '\033[32mALL CHECKS PASSED\033[0m (%d)\n' "$PASS"
else
    printf '\033[31m%d CHECK(S) FAILED\033[0m\n' "$FAIL"
    exit 1
fi
