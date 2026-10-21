#!/usr/bin/env bash
# ACT 基线训练。
# 用法: bash scripts/05_train_act.sh <task> [seed] [gpu]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV="$ROOT/envs/robotwin/.venv"
ROBOTWIN="$ROOT/third_party/RoboTwin"
TASK="${1:-handover_block}"
SEED="${2:-0}"
GPU="${3:-0}"
BATCH_SIZE="${BATCH_SIZE:-8}"
EPOCHS="${EPOCHS:-6000}"

mkdir -p "$ROOT/outputs/logs"
LOG="$ROOT/outputs/logs/act_train_${TASK}_seed${SEED}_$(date +%Y%m%d_%H%M%S).log"

cd "$ROBOTWIN/XPolicyLab/policy/ACT"
echo "[train] task=$TASK seed=$SEED gpu=$GPU batch=$BATCH_SIZE epochs=$EPOCHS"
echo "[train] log=$LOG"
PATH="$VENV/bin:$PATH" ACT_BATCH_SIZE="$BATCH_SIZE" ACT_NUM_EPOCHS="$EPOCHS" \
    bash train.sh RoboTwin "$TASK" arx_x5 joint "$SEED" "$GPU" 2>&1 | tee -a "$LOG"

echo "[train] done: $ROBOTWIN/XPolicyLab/policy/ACT/checkpoints/RoboTwin-$TASK-arx_x5-joint-$SEED"
