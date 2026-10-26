# dual_arm_VLA

双臂 VLA 的**仿真数据采集、训练与仿真评估**。

> 当前状态（2026-10-21）：本机 RTX 4050 已跑通
> `RoboTwin 2.0 + XPolicyLab + CuRobo`：50 条 `handover_block` 自采数据、
> ACT 2000-epoch checkpoint、clean 1 条 smoke 评估（0/1）。
> 正式 6000 epoch / 100 episodes 基线建议上 5090。

## 技术栈

```text
RoboTwin 2.0  —— SAPIEN 仿真 / 50 个双臂任务 / 数据生成 / 官方评测协议
XPolicyLab    —— 策略服务 + 统一评估（policy server ⇄ env client）
LeRobot       —— 后续 VLA 微调的数据格式与策略（当前先用 ACT 基线）
```

## 文档

- [开源生态调研](docs/research.md)：RoboTwin / XPolicyLab / LeRobot / OpenVLA-OFT / π0 / SmolVLA 对比与本机约束分析
- [实施计划](docs/plan.md)：架构、里程碑 M0–M6、数据/训练/评估方案、风险与时间估算
- [Runbook](docs/runbook.md)：本机安装、补丁、采集、训练、评估的实际命令
- [任务笔记](docs/task_handover_block.md)：`handover_block` 的观测/动作/成功判定/基线
- [基线报告](docs/baseline_report.md)：本机 50 条自采 → ACT 2000 epoch → 1 条评估的结果、证据与局限
- [实验记录](docs/experiment_log.md)：每次实验的参数与结果
- [Kaggle 部署评估](docs/kaggle_deployment.md)：为什么完整 RoboTwin 闭环在 Kaggle 不可行、Vulkan probe、训练-only 方案
- [云服务器正式闭环](docs/cloud_server_runbook.md)：从 GitHub clone 到 50 条自采、ACT 6000 epoch、clean/randomized 100 episodes 的完整命令（含 4090/A100 与 5090 两条路径）

## 快速开始

```bash
make check                       # GPU / torch / SAPIEN / CuRobo / 资产自检
make collect EPISODES=50         # 自采 50 条 handover_block clean 数据
make prepare                     # 映射 XPolicyLab 布局 + ACT 预处理
make train EPOCHS=2000 BATCH_SIZE=4
make eval EVAL_EPISODES=20
make summarize                   # -> outputs/results.csv
```

## 环境

- 本机：RTX 4050 Laptop 6GB / 14GB RAM；Ubuntu 24.04
- RoboTwin：uv 管理的 Python 3.10 + torch 2.4.1+cu121 + SAPIEN 3.0.0b1
- CUDA 12.4 toolkit 仅用于编译 CuRobo（项目内 `.cuda`，不污染系统）
- 5090 迁移：torch 2.7.1+cu128 / CUDA 12.8 / `TORCH_CUDA_ARCH_LIST=12.0` / OIDN 2.3.3 补丁

## 下一步

跑完 50 条 → ACT 训练 → clean 评估，记录成功率与视频；再考虑 randomized 和 VLA 微调。
