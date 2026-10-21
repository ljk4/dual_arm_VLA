#!/usr/bin/env bash
# 从零搭 RoboTwin + XPolicyLab + CuRobo（本机 4050 / 5090 通用，5090 需换 torch）。
# 幂等：已存在的目录/环境会跳过或复用。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROBOTWIN="$ROOT/third_party/RoboTwin"
VENV="$ROOT/envs/robotwin/.venv"
PY="$VENV/bin/python"
CUDA_PREFIX="$ROOT/envs/robotwin/.cuda"
CUDA_HOME="$ROOT/envs/robotwin/.cuda_home"
ROBOTWIN_COMMIT="ea8b21121ebb3cd201ff5b3fe361944ac94eda3f"
CUROBO_TAG="v0.7.8"
CUDA_TOOLKIT_VERSION="${CUDA_TOOLKIT_VERSION:-12.4.1}"

log() { printf '\033[36m[setup]\033[0m %s\n' "$*"; }

for c in uv git unzip conda nvidia-smi; do
    command -v "$c" >/dev/null || { echo "missing command: $c" >&2; exit 1; }
done

# 1) RoboTwin code + submodule
if [[ ! -d "$ROBOTWIN/.git" ]]; then
    log "clone RoboTwin"
    git clone --depth 1 --single-branch https://github.com/RoboTwin-Platform/RoboTwin.git "$ROBOTWIN"
fi
log "RoboTwin HEAD: $(git -C "$ROBOTWIN" rev-parse --short HEAD) (pinned: ${ROBOTWIN_COMMIT:0:7})"
git -C "$ROBOTWIN" submodule update --init --recursive

# 2) uv environment
log "uv sync"
uv sync --project "$ROOT/envs/robotwin"

# 3) upstream patches (SAPIEN / mplib / ACT / XPolicyLab uv)
log "apply patches"
"$PY" "$ROOT/scripts/patches/apply_upstream_patches.py"

# 4) XPolicyLab editable
log "install XPolicyLab"
uv pip install --python "$PY" -e "$ROBOTWIN/XPolicyLab"

# 5) embodiment configs: *_tmp.yml -> *.yml with absolute paths
if [[ ! -f "$ROBOTWIN/assets/embodiments/aloha-agilex/curobo_left.yml" ]]; then
    log "generate embodiment configs"
    (cd "$ROBOTWIN" && "$PY" scripts/update_embodiment_config_path.py)
fi

# 6) project-local CUDA toolkit (build only; 5090 请改 12.8)
if [[ ! -x "$CUDA_HOME/bin/nvcc" ]]; then
    log "install CUDA ${CUDA_TOOLKIT_VERSION} toolkit into $CUDA_PREFIX"
    conda create -p "$CUDA_PREFIX" --override-channels -c defaults cuda-toolkit="${CUDA_TOOLKIT_VERSION}" -y
    mkdir -p "$CUDA_HOME"
    ln -sfn ../.cuda/bin "$CUDA_HOME/bin"
    ln -sfn ../.cuda/targets/x86_64-linux/include "$CUDA_HOME/include"
    ln -sfn ../.cuda/targets/x86_64-linux/lib "$CUDA_HOME/lib64"
    ln -sfn ../.cuda/nvvm "$CUDA_HOME/nvvm"
fi

# 7) CuRobo v0.7.8 (sm_89 / sm_120 via TORCH_CUDA_ARCH_LIST)
if [[ ! -d "$ROBOTWIN/envs/curobo/.git" ]]; then
    log "clone CuRobo $CUROBO_TAG"
    git clone --depth 1 --branch "$CUROBO_TAG" https://github.com/NVlabs/curobo.git "$ROBOTWIN/envs/curobo"
fi
ARCH="$("$PY" -c 'import torch; a=torch.cuda.get_device_capability(); print(f"{a[0]}.{a[1]}")')"
log "build CuRobo for sm_$ARCH"
(
    cd "$ROBOTWIN/envs/curobo"
    CUDA_HOME="$CUDA_HOME" TORCH_CUDA_ARCH_LIST="$ARCH" MAX_JOBS="${MAX_JOBS:-2}" \
    NVCC_PREPEND_FLAGS="-allow-unsupported-compiler" \
    uv pip install --python "$PY" -e . --no-build-isolation
)

log "verify"
"$ROOT/scripts/00_check_env.sh"
