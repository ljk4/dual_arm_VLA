#!/usr/bin/env bash
# 下载 RoboTwin 资产。默认只下 objects + embodiments（clean 数据够用），
# WITH_TEXTURES=1 时再下 11GB 背景纹理（randomized 需要）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$ROOT/envs/robotwin/.venv/bin/python"
ROBOTWIN="$ROOT/third_party/RoboTwin"
ASSETS="$ROBOTWIN/assets"

export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
patterns='"objects.zip", "embodiments.zip"'
if [[ "${WITH_TEXTURES:-0}" == "1" ]]; then
    patterns='"background_texture.zip", "objects.zip", "embodiments.zip"'
fi

mkdir -p "$ASSETS"
"$PY" - "$ASSETS" "$patterns" <<'PY'
import sys
from huggingface_hub import snapshot_download
assets, patterns = sys.argv[1], sys.argv[2]
snapshot_download(
    repo_id="TianxingChen/RoboTwin2.0",
    allow_patterns=[p.strip().strip('"') for p in patterns.split(",")],
    local_dir=assets,
    repo_type="dataset",
    resume_download=True,
)
print("download done")
PY

cd "$ASSETS"
for z in *.zip; do
    [[ -f "$z" ]] || continue
    echo "[assets] unzip $z"
    unzip -q -o "$z" -d .
done

cd "$ROBOTWIN"
"$PY" scripts/update_embodiment_config_path.py

echo "[assets] done: $(du -sh "$ASSETS" | cut -f1)"
