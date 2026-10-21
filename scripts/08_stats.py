#!/usr/bin/env python3
"""自采 HDF5 数据的基本统计与健康检查。"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import h5py
import numpy as np

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--task", default="handover_block")
    ap.add_argument("--config", default="demo_clean")
    ap.add_argument("--embodiment", default="aloha_agilex")
    ap.add_argument("--out", type=Path, default=None)
    args = ap.parse_args()

    data_dir = ROOT / "third_party" / "RoboTwin" / "data" / args.config / args.task / args.embodiment / "data"
    files = sorted(data_dir.glob("episode_*.hdf5"))
    if not files:
        raise SystemExit(f"no episodes under {data_dir}")

    lengths, action_min, action_max, action_mean = [], None, None, None
    left_grip, right_grip = [], []
    for p in files:
        with h5py.File(p, "r") as f:
            n = f["action/left_arm_joint_states"].shape[0]
            lengths.append(n)
            a = np.concatenate([
                f["action/left_arm_joint_states"][:],
                f["action/left_ee_joint_states"][:],
                f["action/right_arm_joint_states"][:],
                f["action/right_ee_joint_states"][:],
            ], axis=1)
            action_min = a.min(0) if action_min is None else np.minimum(action_min, a.min(0))
            action_max = a.max(0) if action_max is None else np.maximum(action_max, a.max(0))
            action_mean = a.mean(0) if action_mean is None else action_mean + a.mean(0)
            left_grip.append(f["action/left_ee_joint_states"][:, 0])
            right_grip.append(f["action/right_ee_joint_states"][:, 0])

    action_mean /= len(files)
    lg = np.concatenate(left_grip)
    rg = np.concatenate(right_grip)
    summary = {
        "task": args.task,
        "config": args.config,
        "embodiment": args.embodiment,
        "episodes": len(files),
        "length": {"min": int(min(lengths)), "max": int(max(lengths)),
                   "mean": float(np.mean(lengths))},
        "action_dim": int(action_min.shape[0]),
        "action_min": action_min.round(4).tolist(),
        "action_max": action_max.round(4).tolist(),
        "action_mean": action_mean.round(4).tolist(),
        "left_gripper": {"min": float(lg.min()), "max": float(lg.max()),
                          "mean": float(lg.mean()), "closed_frac": float((lg < 0.05).mean())},
        "right_gripper": {"min": float(rg.min()), "max": float(rg.max()),
                           "mean": float(rg.mean()), "closed_frac": float((rg < 0.05).mean())},
    }
    out = args.out or ROOT / "outputs" / "stats" / f"{args.task}_{args.config}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(summary, ensure_ascii=False, indent=2))
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    print(f"\nwrote {out}")


if __name__ == "__main__":
    main()
