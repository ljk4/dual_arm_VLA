# 实验记录

> 一条实验一行；详细命令看 `docs/runbook.md`，任务定义看 `docs/task_handover_block.md`。

| 日期 | 实验 ID | 任务 | 训练数据 | 策略 | epochs / batch | 评估设置 | episodes | 成功率 | 备注 |
| --- | --- | --- | --- | --- | --- | --- | ---: | ---: | --- |
| 2026-10-21 | data-handover-clean-50 | handover_block | 自采 50 clean | — | — | — | — | — | 50 条全部成功；原始 812MB；285 帧/条，14 维 joint；预处理 320×240 后 9.1GB |
| 2026-10-21 | act-handover-clean-v1 | handover_block | 自采 50 clean | ACT | 2000 / 8 | clean | 1 | 0.0 | 320×240；训练 52:40，峰值 ~3.5GB；6GB 下 CPU policy eval；**smoke only，不能引用为真实成功率**；详见 baseline_report.md |

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
