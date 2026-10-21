# ACT 基线报告：`handover_block`（本机 RTX 4050）

> 日期：2026-10-21
> 结论一句话：**本机垂直切片跑通**（50 条自采 → ACT 2000 epoch → clean 1 条评估 0/1），
> 但这是一个 **smoke baseline**，不是可对外比较的正式基线；正式基线建议上 5090 跑 6000 epoch + 100 episodes。

## 1. 结果摘要

| 项 | 结果 |
| --- | --- |
| 数据 | **50 条**自采 `demo_clean`，全部成功；原始 HDF5 812MB |
| episode 长度 | 272–304 帧，均值 **282.4**，30 FPS |
| 动作维度 | 14（双 6 关节 + 双夹爪），joint 空间 |
| 策略 | ACT，320×240，batch 8，2000 epoch |
| 训练耗时 | **52 分 40 秒**（RTX 4050 6GB） |
| 训练峰值显存 | 约 **3.5GB** |
| 评估 | clean，1 episode，**0/1 = 0.0%** |
| 视频 | 800 帧，`episode0.mp4` |
| 失败表现 | 机械臂接近红色块，但没有完成抓取/抬起/换手 |

> 1 条 episode 的 0% 不能代表策略真实水平；它只说明「评估管线能完整跑完并产出结果」。
> 以 2000/6000 epoch 的训练量和 1 条评估计，这个结果是**欠拟合 + 样本不足**的预期表现。

## 2. 证据与产物

| 产物 | 路径 |
| --- | --- |
| 训练日志 | `outputs/logs/act_train_handover_block_seed0_*.log` |
| 最终 checkpoint | `third_party/RoboTwin/XPolicyLab/policy/ACT/checkpoints/RoboTwin-handover_block-arx_x5-joint-0/policy_epoch_2000_seed_0.ckpt` |
| 评估日志 | `outputs/logs/act_eval_handover_block_demo_clean_*.log` |
| 评估结果 | `third_party/RoboTwin/eval_result/handover_block/ACT/demo_clean/RoboTwin-handover_block-arx_x5-joint-0/2026-10-21_19-34-35_002970/_result.txt` |
| 评估视频 | 同目录 `episode0.mp4` |
| 数据统计 | `outputs/stats/handover_block_demo_clean.json` |
| CSV 汇总 | `outputs/results.csv` |
| 可视化 | `outputs/viz/handover_head_contact_sheet.png`（专家）、`outputs/viz/eval_2000ep_contact_sheet.png`（策略） |

`_result.txt` 内容：

```text
Timestamp: 2026-10-21_19-34-35_002970

Instruction Type: seen

0.0
```

## 3. 复现命令

```bash
# 1) 50 条自采（本机约 50 分钟）
bash scripts/03_collect_data.sh handover_block demo_clean 50 0

# 2) 320×240 预处理（50 条约 30 秒，9.1GB）
ACT_IMAGE_W=320 ACT_IMAGE_H=240 bash scripts/04_prepare_act.sh handover_block demo_clean

# 3) 2000 epoch 训练（约 53 分钟）
EPOCHS=2000 BATCH_SIZE=8 bash scripts/05_train_act.sh handover_block 0 0

# 4) 1 条评估（6GB 限制：CPU policy server，约 5 分钟）
ACT_DEVICE=cpu EXPERT_CHECK=0 ACT_IMAGE_W=320 ACT_IMAGE_H=240 \
  bash scripts/06_eval_act.sh handover_block demo_clean 0 \
  RoboTwin-handover_block-arx_x5-joint-0 1

# 5) 汇总
envs/robotwin/.venv/bin/python scripts/07_summarize_eval.py
```

## 4. 为什么本机只能做到这里

### 4.1 6GB 上 GPU 策略 + 仿真冲突

只要 policy server 用 `cuda:0`，SAPIEN 在第一次 `get_obs()` 的
`left_camera.take_picture()` 就报：

```text
RuntimeError: cannot create buffer
```

已验证不是 OIDN、也不是 RT samples 的问题（把 samples 降到 1、关闭 denoiser 仍复现）；
CPU policy server 则完全正常。结论：**4050 6GB 上「第二个 CUDA 进程 + Vulkan 渲染」不可行**，
不是代码 bug。正式 100-episode 评估需要更大显存（5090 32GB）或改造成同进程推理。

### 4.2 评估速度

CPU policy server（`temporal_agg=false`，每 50 步推理一次）下：
1 条 800 步 episode 约 **5 分钟**；20 条约 1.5–2 小时，100 条不现实。

### 4.3 训练量

- 官方 ACT 设置是 **6000 epoch**；本次只跑了 2000（约 1/3）。
- 视觉上策略学会了「靠近块」，但没有学会「抓取—抬起—换手」的完整序列。
- 320×240 是相机原生分辨率；官方脚本默认上采样到 640×480，信息量相同但更慢。

## 5. 局限与偏差（必须随结果一起引用）

1. **评估只有 1 条**，置信区间极大；不能引用为 ACT 在 `handover_block` 上的真实成功率。
2. **2000 epoch < 官方 6000**，属于欠拟合。
3. **`EXPERT_CHECK=0`**：跳过了官方评估里的专家预检；seed 未过滤，协议与 leaderboard 不完全一致。
4. **`temporal_agg=false`**：为了 CPU 推理把 temporal aggregation 关了，和官方 ACT 部署有差异。
5. **320×240**：与官方 640×480 预处理不同（但原始数据是 320×240）。
6. 6GB 上无法同时跑 GPU policy + 仿真，评估侧不是 leaderboard 标准配置。

## 6. 下一步（5090 正式基线）

1. 在 5090 上建独立 uv 环境：torch 2.7.1+cu128、CUDA 12.8、`TORCH_CUDA_ARCH_LIST=12.0`、
   OIDN 2.3.3 补丁（见 `docs/runbook.md`）。
2. 同步 50 条 HDF5（812MB），重新预处理（可在 5090 上直接 640×480）。
3. ACT 训练 **6000 epoch**（5090 预计 10–20 分钟量级），保留 `SAVE_FREQ=1000` 以便比较。
4. 评估 **100 episodes × 2 seeds**，`EXPERT_CHECK=1`，GPU policy server（32GB 足够），
   记录 clean / randomized 两套结果。
5. 如果 6000 epoch 仍低，再考虑：更多自采数据（100–200 条）、域随机化、或换 VLA（SmolVLA/OpenVLA-OFT）。

## 7. 结论

- **工程闭环已经成立**：uv 环境、SAPIEN/CuRobo、自采 50 条、ACT 训练、XPolicyLab 评估、结果/视频/文档全部打通。
- **科学结论尚未成立**：1 条 0/1 不能说明 ACT 在这个任务上的水平；需要 5090 上的正式训练与 100-episode 评估。
- 本机 4050 的定位：**开发、可视化、单条 smoke**；正式训练/评估放 5090。
