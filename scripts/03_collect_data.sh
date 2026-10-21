#!/usr/bin/env bash
# 自采数据：修改 episode_num 后调用 RoboTwin 的 collect_data.sh。
# 用法: bash scripts/03_collect_data.sh <task> <config> <episodes> [gpu]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$ROOT/envs/robotwin/.venv/bin/python"
ROBOTWIN="$ROOT/third_party/RoboTwin"

TASK="${1:-handover_block}"
CONFIG="${2:-demo_clean}"
EPISODES="${3:-50}"
GPU="${4:-0}"

CFG="$ROBOTWIN/env_cfg/task_config/${CONFIG}.yml"
[[ -f "$CFG" ]] || { echo "missing config: $CFG" >&2; exit 1; }

"$PY" - "$CFG" "$EPISODES" <<'PY'
import re, sys
path, episodes = sys.argv[1], int(sys.argv[2])
text = open(path).read()
text, n = re.subn(r'(?m)^episode_num:\s*\d+', f'episode_num: {episodes}', text)
if n != 1:
    raise SystemExit(f'episode_num not found exactly once in {path}')
open(path, 'w').write(text)
print(f'[{path}] episode_num={episodes}')
PY

mkdir -p "$ROOT/outputs/logs"
LOG="$ROOT/outputs/logs/collect_${TASK}_${CONFIG}_$(date +%Y%m%d_%H%M%S).log"

cd "$ROBOTWIN"
echo "[collect] task=$TASK config=$CONFIG episodes=$EPISODES gpu=$GPU"
echo "[collect] log=$LOG"
export PYTHONUNBUFFERED=1
CUDA_VISIBLE_DEVICES="$GPU" PATH="$ROOT/envs/robotwin/.venv/bin:$PATH" \
    bash collect_data.sh "$TASK" "$CONFIG" "$GPU" 2>&1 | tee -a "$LOG"

echo "[collect] done: $ROBOTWIN/data/$CONFIG/$TASK/aloha_agilex"
