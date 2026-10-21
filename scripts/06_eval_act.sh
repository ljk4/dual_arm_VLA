#!/usr/bin/env bash
# ACT 评估（XPolicyLab policy server + RoboTwin 仿真 client，均使用 uv venv）。
# 用法: bash scripts/06_eval_act.sh <task> <eval_config> [seed] [run_name] [episodes]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV="$ROOT/envs/robotwin/.venv"
ROBOTWIN="$ROOT/third_party/RoboTwin"
TASK="${1:-handover_block}"
EVAL_CONFIG="${2:-demo_clean}"
SEED="${3:-0}"
RUN_NAME="${4:-RoboTwin-$TASK-arx_x5-joint-$SEED}"
EPISODES="${5:-100}"
EXPERT_CHECK="${EXPERT_CHECK:-1}"
if [[ "$EXPERT_CHECK" == "1" || "$EXPERT_CHECK" == "true" ]]; then
    EXPERT_CHECK_ARG="True"
else
    EXPERT_CHECK_ARG="False"
fi

ACT_DIR="$ROBOTWIN/XPolicyLab/policy/ACT"
CKPT="$ACT_DIR/checkpoints/$RUN_NAME"
[[ -d "$CKPT" ]] || { echo "missing checkpoint: $CKPT" >&2; exit 1; }

mkdir -p "$ROOT/outputs/logs"
LOG="$ROOT/outputs/logs/act_eval_${TASK}_${EVAL_CONFIG}_${RUN_NAME}_$(date +%Y%m%d_%H%M%S).log"
ARGS_FILE="$(mktemp)"
trap 'rm -f "$ARGS_FILE"' EXIT
printf -- '--task_config\n%s\n--test_num\n%s\n--instruction_type\nseen\n--expert_check\n%s\n' \
    "$EVAL_CONFIG" "$EPISODES" "$EXPERT_CHECK_ARG" > "$ARGS_FILE"

echo "[eval] task=$TASK eval_config=$EVAL_CONFIG run=$RUN_NAME episodes=$EPISODES expert_check=$EXPERT_CHECK_ARG"
echo "[eval] log=$LOG"
cd "$ACT_DIR"
ROBOTWIN_EVAL_ARGS_FILE="$ARGS_FILE" PATH="$VENV/bin:$PATH" \
    bash eval.sh RoboTwin "$TASK" "$RUN_NAME" arx_x5 joint "$SEED" 0 0 "$VENV" "$VENV" \
    2>&1 | tee -a "$LOG"
