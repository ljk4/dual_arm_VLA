#!/usr/bin/env bash
# 将 RoboTwin 自采数据映射到 XPolicyLab ACT 期望的目录布局，并预处理。
# 用法: bash scripts/04_prepare_act.sh <task> [config]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV="$ROOT/envs/robotwin/.venv"
PY="$VENV/bin/python"
ROBOTWIN="$ROOT/third_party/RoboTwin"
TASK="${1:-handover_block}"
CONFIG="${2:-demo_clean}"

SRC="$ROBOTWIN/data/$CONFIG/$TASK/aloha_agilex"
[[ -d "$SRC/data" ]] || { echo "missing raw data: $SRC/data" >&2; exit 1; }

# XPolicyLab ACT 约定: data/<bench>/<task>/<env_cfg_type>/
# env_cfg_type 用 arx_x5（与 aloha-agilex 的 action dim 对齐）
DST="$ROBOTWIN/data/RoboTwin/$TASK/arx_x5"
mkdir -p "$(dirname "$DST")"
ln -sfn "../../$CONFIG/$TASK/aloha_agilex" "$DST"
echo "[prepare] $DST -> $(readlink "$DST")"

cd "$ROBOTWIN/XPolicyLab/policy/ACT"
PATH="$VENV/bin:$PATH" bash process_data.sh RoboTwin "$TASK" arx_x5 joint

echo "[prepare] done: $ROBOTWIN/XPolicyLab/policy/ACT/processed_data/RoboTwin/$TASK/arx_x5-joint"
