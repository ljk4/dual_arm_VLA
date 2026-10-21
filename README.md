# dual_arm_VLA

双臂 VLA 的**仿真数据采集、训练与仿真评估**。

> 状态：规划阶段（尚未安装仿真/训练环境）

## 技术栈

```text
RoboTwin 2.0  —— SAPIEN 仿真 / 50 个双臂任务 / 数据生成 / 官方评测协议
XPolicyLab    —— 策略服务 + 统一评估（policy server ⇄ env client）
LeRobot       —— LeRobotDataset v3 + ACT / DP / SmolVLA / π0 等策略
```

## 文档

- [开源生态调研](docs/research.md)：RoboTwin / XPolicyLab / LeRobot / OpenVLA-OFT / π0 / SmolVLA 对比与本机约束分析
- [实施计划](docs/plan.md)：架构、里程碑 M0–M6、数据/训练/评估方案、风险与时间估算

## 本机约束

- RTX 4050 Laptop **6GB** VRAM / 14GB RAM / 144GB 可用磁盘
- 本机目标：ACT 闭环 → SmolVLA 优化；7B 级 VLA 需 24GB+ 云 GPU

## 环境隔离

- 本仓库：Python 3.12 + uv（只做编排、数据统计、结果汇总）
- RoboTwin：conda `python=3.10` + CUDA 12.1 + SAPIEN 3.0.0b1
- LeRobot：按策略单独建环境

## 下一步

见 [计划中的「需要确认」](docs/plan.md#11-下一步需要你确认)，确认云端 GPU / 任务范围 / 数据方式后从 M0 开始。
