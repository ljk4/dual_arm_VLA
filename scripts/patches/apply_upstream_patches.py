#!/usr/bin/env python3
"""对上游做最小、可重复的补丁（幂等）。

这些补丁不 fork 上游，只修：
- SAPIEN URDF loader 的编码 / .srdf 路径；
- mplib screw planner 的 collide 判断；
- ACT train.sh 的 batch/epoch 环境变量；
- XPolicyLab 评估脚本对 uv venv 路径的支持。
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VENV_SITE = ROOT / "envs" / "robotwin" / ".venv" / "lib" / "python3.10" / "site-packages"
ROBOTWIN = ROOT / "third_party" / "RoboTwin"


def patch(path: Path, old: str, new: str, marker: str, label: str) -> None:
    if not path.exists():
        raise SystemExit(f"missing file: {path}")
    text = path.read_text()
    if marker in text:
        print(f"[skip] {label} (already patched)")
        return
    if old not in text:
        raise SystemExit(f"[fail] {label}: anchor not found in {path}")
    path.write_text(text.replace(old, new, 1))
    print(f"[ok]   {label}")


def main() -> None:
    if not VENV_SITE.exists():
        raise SystemExit(f"missing venv: {VENV_SITE} (run uv sync --project envs/robotwin)")

    sapien = VENV_SITE / "sapien" / "wrapper" / "urdf_loader.py"
    patch(sapien,
          'with open(urdf_file, "r") as f:',
          'with open(urdf_file, "r", encoding="utf-8") as f:',
          'open(urdf_file, "r", encoding="utf-8")',
          "sapien urdf_file utf-8")
    patch(sapien,
          'with open(srdf_file, "r") as f:',
          'with open(srdf_file, "r", encoding="utf-8") as f:',
          'open(srdf_file, "r", encoding="utf-8")',
          "sapien srdf_file utf-8")
    patch(sapien,
          'urdf_file[:-4] + "srdf"',
          'urdf_file[:-4] + ".srdf"',
          'urdf_file[:-4] + ".srdf"',
          "sapien srdf suffix")

    mplib = VENV_SITE / "mplib" / "planner.py"
    patch(mplib,
          " < 1e-4 or collide or not within_joint_limit:",
          " < 1e-4 or not within_joint_limit:",
          " < 1e-4 or not within_joint_limit:",
          "mplib screw planner")

    train = ROBOTWIN / "XPolicyLab" / "policy" / "ACT" / "train.sh"
    patch(train,
          "--batch_size 16",
          "--batch_size ${ACT_BATCH_SIZE:-16}",
          "ACT_BATCH_SIZE",
          "ACT batch size env")
    patch(train,
          "--num_epochs 6000",
          "--num_epochs ${ACT_NUM_EPOCHS:-6000}",
          "ACT_NUM_EPOCHS",
          "ACT epochs env")

    server = ROBOTWIN / "XPolicyLab" / "policy" / "ACT" / "setup_eval_policy_server.sh"
    old = ('source "$(conda info --base)/etc/profile.d/conda.sh"\n'
           'conda activate "${policy_conda_env}"')
    new = ('if [[ -d "${policy_conda_env}" && -x "${policy_conda_env}/bin/python" ]]; then\n'
           '    export PATH="${policy_conda_env}/bin:${PATH}"\n'
           'else\n'
           '    source "$(conda info --base)/etc/profile.d/conda.sh"\n'
           '    conda activate "${policy_conda_env}"\n'
           'fi')
    patch(server, old, new, 'policy_conda_env}/bin/python', "XPolicyLab server uv venv")

    client = ROBOTWIN / "XPolicyLab" / "utils" / "run_sim_env_client.sh"
    old = ('source "$(conda info --base)/etc/profile.d/conda.sh"\n'
           'conda deactivate || true\n'
           'conda activate "${eval_env_conda_env}"')
    new = ('if [[ -d "${eval_env_conda_env}" && -x "${eval_env_conda_env}/bin/python" ]]; then\n'
           '    export PATH="${eval_env_conda_env}/bin:${PATH}"\n'
           'else\n'
           '    source "$(conda info --base)/etc/profile.d/conda.sh"\n'
           '    conda deactivate || true\n'
           '    conda activate "${eval_env_conda_env}"\n'
           'fi')
    patch(client, old, new, 'eval_env_conda_env}/bin/python', "XPolicyLab client uv venv")

    setup_client = ROBOTWIN / "XPolicyLab" / "utils" / "setup_env_client.sh"
    anchor = 'deploy_meta="$('
    new = ('if [[ -d "${eval_env_conda_env}" && -x "${eval_env_conda_env}/bin/python" ]]; then\n'
           '    export PATH="${eval_env_conda_env}/bin:${PATH}"\n'
           'fi\n\n'
           'deploy_meta="$(')
    patch(setup_client, anchor, new, 'eval_env_conda_env}/bin/python', "XPolicyLab setup client uv venv")

    print("\nall patches applied")


if __name__ == "__main__":
    sys.exit(main())
