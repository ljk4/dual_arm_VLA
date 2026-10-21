#!/usr/bin/env python3
"""汇总 RoboTwin/XPolicyLab 评估结果 _result.txt -> CSV。"""
from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_EVAL = ROOT / "third_party" / "RoboTwin" / "eval_result"
DEFAULT_OUT = ROOT / "outputs" / "results.csv"


def parse_result(path: Path) -> tuple[float | None, str]:
    text = path.read_text(errors="ignore")
    m = re.search(r"^\s*([0-9.]+)\s*$", text, re.M)
    if not m:
        return None, ""
    return float(m.group(1)), text.strip().splitlines()[0] if text.strip() else ""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--eval-root", type=Path, default=DEFAULT_EVAL)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = ap.parse_args()

    rows = []
    for result in sorted(args.eval_root.glob("**/_result.txt")):
        rel = result.relative_to(args.eval_root)
        # <task>/<policy>/<config>/<ckpt>/<timestamp>/_result.txt
        parts = rel.parts
        if len(parts) < 5:
            continue
        task, policy, config, ckpt, stamp = parts[:5]
        rate, first_line = parse_result(result)
        rows.append({
            "date": stamp,
            "task": task,
            "policy": policy,
            "eval_config": config,
            "checkpoint": ckpt,
            "success_rate": "" if rate is None else f"{rate:.4f}",
            "result_file": str(result),
        })

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()) if rows else [
            "date", "task", "policy", "eval_config", "checkpoint", "success_rate", "result_file"
        ])
        w.writeheader()
        w.writerows(rows)
    print(f"wrote {len(rows)} rows -> {args.out}")


if __name__ == "__main__":
    main()
