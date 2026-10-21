# 实验记录

> 一条实验一行；详细命令看 `docs/runbook.md`，任务定义看 `docs/task_handover_block.md`。

| 日期 | 实验 ID | 任务 | 训练数据 | 策略 | epochs / batch | 评估设置 | episodes | 成功率 | 备注 |
| --- | --- | --- | --- | --- | --- | --- | ---: | ---: | --- |
| 2026-10-21 | data-handover-clean-50 | handover_block | 自采 50 clean | — | — | — | — | — | 采集脚本：`scripts/03_collect_data.sh`；HDF5 285 帧/条，14 维 joint |
| 2026-10-21 | act-handover-clean-v1 | handover_block | 自采 50 clean | ACT | 待填 | clean | 待填 | 待填 | 第一版基线 |

## 记录模板

```text
日期:
实验 ID:
任务:
训练数据: <config> / <episodes> 条自采
策略: ACT / DP / SmolVLA / ...
超参: epochs=, batch=, lr=, chunk=, camera=
评估: <task_config> / <episodes> episodes / seed
结果: success_rate=, avg_len=, peak_vram=, wall_clock=
产物: 日志路径、checkpoint、视频目录
结论 / 下一步:
```
