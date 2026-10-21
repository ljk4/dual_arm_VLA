# 双臂 VLA 仿真：实施计划

> 配套调研见 [`research.md`](./research.md)。
> 原则：**不 fork、不重写仿真器/数据格式/评估协议**；本仓库只做编排、配置、适配和实验分析。
> 所有上游以固定 commit 引入，改动优先走配置或薄适配层，必要时向上游提 PR。

---

## 1. 目标与非目标

### 目标

1. 在仿真中完成**双臂数据采集**（预采集数据下载 + 自定义域随机化合成）。
2. 完成至少一种策略的**训练**（本机 ACT；进阶 SmolVLA；可选云端 VLA）。
3. 完成**仿真评估**，产出可复现的成功率、视频与实验记录（clean vs randomized）。
4. 沉淀一套可重复执行的脚本和文档，换机器/换任务能快速复现。

### 非目标（第一阶段不做）

- 真机部署 / sim-to-real 迁移；
- 从零训练 VLA 主干；
- 50 个任务的全量 benchmark（先 1–5 个任务，验证后再扩）；
- 灵巧手 / 移动底盘 / 多机协作。

---

## 2. 技术选型

| 层 | 选择 | 说明 |
| --- | --- | --- |
| 仿真 / 任务 / 数据 | **RoboTwin 2.0** | SAPIEN，50 双臂任务，clean/randomized，官方数据生成器 |
| 评估 / 策略服务 | **XPolicyLab** | RoboTwin 官方评估入口，支持 policy server 分机部署 |
| 数据格式 / 训练 | **LeRobot v3** | ACT / DP / SmolVLA 原生；RoboTwin 提供转换脚本 |
| 本机基线 | **ACT** → DP（可选） | 6GB 可训，先把闭环跑通 |
| 本机 VLA（进阶） | **SmolVLA 450M** | 冻结 VLM + 只训 action expert，压到 6GB 需要调参 |
| 云端 VLA（可选） | **OpenVLA-OFT 7B** 或 **π0.5 3B** | 24–48GB；用 XPolicyLab 远程 policy server 接本地仿真 |

**环境隔离**：

- 本仓库 Python 3.12（uv）：只放编排、数据分析、结果汇总；
- RoboTwin / XPolicyLab 用 conda `python=3.10`（torch 2.4.1 + SAPIEN 3.0.0b1）；
- LeRobot 训练环境按策略单独建（ACT / SmolVLA 依赖不同），不要和 RoboTwin 混装。

---

## 3. 总体架构

```text
┌──────────────────────────── 本仓库（编排层） ────────────────────────────┐
│ configs/       任务、训练、评估配置                                      │
│ scripts/       setup / download / convert / train / eval / summarize     │
│ src/           数据统计、结果解析、实验看板（薄 Python 包）               │
└───────────────┬───────────────────────────────┬──────────────────────────┘
                │                               │
      ┌─────────▼─────────┐           ┌─────────▼─────────┐
      │ RoboTwin 2.0      │           │ LeRobot           │
      │ SAPIEN 仿真        │           │ LeRobotDataset v3 │
      │ collect_data.sh   │──HDF5────▶│ ACT / DP / SmolVLA│
      │ eval_policy.sh    │           │ lerobot-train     │
      └─────────┬─────────┘           └─────────┬─────────┘
                │                               │
                │        ┌──────────────────────▼──────────┐
                └───────▶│ XPolicyLab                      │
                         │ policy server ⇄ env client (ws)  │
                         │ eval_policy.sh multitask         │
                         └──────────────────────────────────┘
```

数据流：

```text
预采集数据 / 自采 HDF5
   → decode_image_bit 校验
   → LeRobot v3（Parquet + MP4）
   → 训练（ACT / DP / SmolVLA / 云端 VLA）
   → XPolicyLab checkpoint
   → RoboTwin 仿真评估（clean / randomized）
   → eval_result/*.json + 视频 → 汇总 CSV
```

---

## 4. 仓库结构（计划）

```text
dual_arm_VLA/
├── README.md
├── pyproject.toml                 # 本仓库编排工具（py3.12，uv）
├── docs/
│   ├── research.md                # 调研
│   ├── plan.md                    # 本文
│   └── runbook.md                 # 后续：逐步操作手册 / 踩坑记录
├── configs/
│   ├── tasks.yaml                 # 选中的任务、本体、相机、action_type
│   ├── train/
│   │   ├── act.yaml
│   │   ├── dp.yaml
│   │   └── smolvla_6gb.yaml
│   └── eval/
│       ├── single_task.yml        # 单任务快速评估
│       └── clean_vs_randomized.yml
├── scripts/
│   ├── 00_check_env.sh            # 检查 GPU / Vulkan / 磁盘 / 网络
│   ├── 01_setup_robotwin.sh       # 固定 commit 拉取 + 安装 + 资产
│   ├── 02_download_data.sh        # 下载指定任务（含镜像/重试）
│   ├── 03_convert_lerobot.sh      # HDF5 → LeRobot v3
│   ├── 10_train_act.sh
│   ├── 11_train_smolvla.sh
│   ├── 20_eval.sh                 # 调 XPolicyLab eval_policy.sh
│   └── 30_summarize.py            # 汇总 eval_result → results.csv
├── src/dual_arm_vla/
│   ├── data/                      # 数据校验、统计、可视化
│   ├── eval/                      # 结果解析、成功率聚合
│   └── cli.py
├── third_party/                   # gitignore：RoboTwin（固定 commit）
├── data/                          # gitignore：HDF5 / LeRobot 数据集
├── outputs/                       # gitignore：checkpoint / 视频 / 日志
└── .gitignore
```

**边界约定**：

- `third_party/RoboTwin` 不提交，由 `scripts/01_setup_robotwin.sh` 拉取并记录 commit；
- `data/`、`outputs/`、`third_party/` 全部 gitignore；
- 本仓库不复制上游代码；需要改上游时，先在本仓库 `patches/` 留存 patch，并注明上游 commit。

---

## 5. 里程碑

### M0 · 环境与网络（0.5–1 天 + 下载时间）

**任务**

1. 系统依赖（需要用户执行 sudo）：
   ```bash
   sudo apt update
   sudo apt install -y libvulkan1 mesa-vulkan-drivers vulkan-tools ffmpeg
   vulkaninfo --summary   # 应看到 RTX 4050
   ```
2. conda 环境（Python 3.10）：
   ```bash
   conda create -n robotwin python=3.10 -y
   conda activate robotwin
   git clone --recurse-submodules https://github.com/RoboTwin-Platform/RoboTwin.git
   cd RoboTwin
   bash scripts/_install.sh
   ```
3. 资产（约 15GB，**后台/夜间跑**）：
   ```bash
   # 建议走镜像 + 强制 IPv4，避免 fake-IP IPv6 卡住
   export HF_ENDPOINT=https://hf-mirror.com
   bash scripts/_download_assets.sh
   ```
4. 网络兜底：git clone 断连时用 `codeload.github.com` tarball；HF 下载用 `curl -4 -L --retry`；
   必要时 `aria2c -x8 -s8` 多连接。
5. 冒烟测试：单任务、单 episode 采集 + 回放；确认 HDF5 可读、图像颜色正确、动作维度 14。

**验收**

- `vulkaninfo` 正常；`python -c "import sapien, torch; print(torch.cuda.is_available())"` 为 True；
- `collect_data.sh` 能产出至少 1 条 HDF5，`decode_image_bit` 解出的图像颜色正确；
- 记录安装耗时、资产大小、遇到的问题到 `docs/runbook.md`。

**风险提示**：15GB 资产在 0.2MB/s 下要 20h+；如果网络无法改善，优先考虑云端下载后同步，或只解压所需对象/本体。

---

### M1 · 数据垂直切片（1 天）

**任务**

1. 选 2 个任务（建议：`beat_block_hammer` 短程 + `stack_bowls_two` 或 `place_container_plate` 长程）。
2. 下载 clean 50 条/任务（约 0.25GB/任务）：
   ```bash
   bash scripts/download_xpolicylab_data.sh beat_block_hammer stack_bowls_two
   ```
3. 转 LeRobot v3：
   ```bash
   python XPolicyLab/scripts/transform_lerobot_v30_format.py \
     "demo_clean.*.aloha_agilex" \
     --repo_id robotwin_demo_clean_v30 \
     --max_episode 50
   ```
4. 编写 `src/dual_arm_vla/data/inspect.py`：统计 episode 数、帧数、相机键、动作维度、成功率、图像分辨率；
   抽样解码并保存 3 张可视化图。
5. **接线 spike**：确认 XPolicyLab ACT 适配器期望的 `data/<bench_name>/<ckpt_name>/<env_cfg_type>` 布局，
   用软链或小转换脚本对齐；把结论写进 `docs/runbook.md`。

**验收**

- `LeRobotDataset(<repo_id>)` 能加载，`dataset[0]["action"].shape == (14,)`；
- 三个相机键存在且图像颜色正确（红色物体是红色）；
- 数据统计 JSON 落盘：`outputs/stats/<repo_id>.json`。

---

### M2 · ACT 基线 + 评估闭环（1–2 天）

**任务**

1. 安装 ACT 适配器环境：
   ```bash
   cd XPolicyLab/policy/ACT && bash install.sh
   ```
2. 数据处理 / 训练 / 评估（以适配器 README 为准，下面的 `<ckpt>` 是本次 run 名）：
   ```bash
   bash process_data.sh RoboTwin <ckpt> arx_x5 joint
   bash train.sh     RoboTwin <ckpt> arx_x5 joint 0 0
   bash eval.sh      RoboTwin beat_block_hammer <ckpt> arx_x5 joint 0 0 0 <act_env> <robotwin_env>
   ```
3. 先跑 10–20 episodes 冒烟，确认评估脚本、视频、结果 JSON 正常；再按官方配置跑满。
4. 评估两组：训练 clean → 测 clean；训练 clean → 测 randomized（OOD）。
5. 用 `scripts/30_summarize.py` 汇总 `eval_result/`。

**验收**

- 评估能完整跑完，产出 success rate、episode 视频、逐 episode JSON；
- clean 成功率明显高于随机策略（先跑一次 demo/random policy 做 harness 自检）；
- 同配置重跑结果在合理波动范围内。

---

### M3 · Diffusion Policy 基线（1 天，可选）

**任务**：同数据、同评估协议跑 DP；对比 ACT 的成功率、训练时间、显存峰值。
**目的**：确认「策略差异」而非「数据/评估管线差异」，为后续 VLA 提供参照。

**验收**：DP 能训练 + 评估；记录峰值显存；与 ACT 同表对比。

---

### M4 · SmolVLA 6GB 优化（3–5 天）

**任务**

1. 用 LeRobot 直接训练（绕过适配器默认超参，便于控显存）：
   - `batch_size=1`，`grad_accum` 拉回有效 batch；
   - 图像 `256×256`（`resize_imgs_with_padding`）；
   - `freeze_vision_encoder=True`、`train_expert_only=True`（默认已开）；
   - 梯度检查点 / bf16（RTX 4050 支持 bf16）；
   - 先 5k–10k step，确认 loss 正常，再决定是否跑满 5 epoch。
2. 用 `nvidia-smi` 记录峰值；OOM 时按「分辨率 → batch → 冻结更多层 → 云端」顺序降级。
3. 评估接入 XPolicyLab SmolVLA 适配器（checkpoint 指向 LeRobot 输出）。
4. 对比 ACT：clean / randomized 成功率、推理延迟、显存。

**验收**

- 6GB 下能完成至少一次完整训练（不 OOM）；
- 评估能跑完 10–20 episodes；
- 给出「本机可运行配置」和「必须上云的配置」两条结论。

---

### M5 · 云端 VLA（1–2 周，可选）

**前置**：有 24GB+ 云 GPU（4090 24GB / A100 40GB / L40S 48GB）。

**任务**

1. 云端复刻 M0–M1（数据可直接上传，不必重新下载 15GB 资产，如果只在云端训练）。
2. 选一条路线：
   - **OpenVLA-OFT 7B LoRA**（ALOHA 原生，最贴近双臂 VLA）；
   - **π0.5 LoRA**（3B，通用性强，LeRobot/XPolicyLab 都有适配）。
3. 训练数据：3–5 个任务 clean + randomized 子集；单任务先跑通，再多任务混训。
4. 评估：
   - 方案 A：云端同时跑仿真 + 策略（最快）；
   - 方案 B：云端 policy server + 本地仿真（XPolicyLab 分机部署，验证「小显存本机也能评估大模型」）。
5. 产出与 ACT/SmolVLA 的对比表（成功率、OOD 掉点、推理频率、成本）。

**验收**

- 至少一个 VLA 在 1 个任务上完成 clean/randomized 评估；
- 有可复现的训练/评估命令与成本记录。

---

### M6 · 自定义任务 / 自采数据（可选，1 周）

**任务**

1. 选一个 RoboTwin 没有的任务，或对现有任务加大域随机化；
2. 改 `env_cfg/task_config/*.yml`（`episode_num`、DR 开关、相机）；
3. `bash collect_data.sh <task> demo_randomized 0` 合成 50–100 条；
4. 训练 + 评估，验证「自采数据 → 策略」闭环；
5. 记录 seed 搜索耗时、成功率、失败模式。

**验收**：自采数据可训练、可评估；与预采集数据的结果可比。

---

## 6. 数据方案

### 6.1 三条数据来源

| 方式 | 工具 | 规模 | 成本 | 适用 |
| --- | --- | --- | --- | --- |
| 下载预采集 | RoboTwin Dataset | 10 万+ 轨迹 | 带宽/磁盘 | 快速起步、复现基线 |
| 自动合成 | `collect_data.sh` + CuRobo + DR | 无上限 | GPU 时间（可能很慢） | 自定义任务、补足 DR 数据 |
| 人类遥操作 | BiDex-100 / ALOHA 类 | 小规模高质量 | 人工 | 灵巧手、精细任务（后续） |

**第一阶段以「下载预采集」为主**，自采只做小规模验证。

### 6.2 任务选择

优先选**专家成功率高、episode 短、双臂协作明显**的任务：

- `beat_block_hammer`（短程、易诊断，适合冒烟）；
- `stack_bowls_two` / `stack_bowls_three`（长程、双臂配合）；
- `handover_block` / `handover_mic`（显式双臂交接，最能体现双臂 VLA 价值）。

第一轮 2 个任务，第二轮扩到 5 个；每个任务 clean 50 条 + randomized 100 条（不跑 500 条全量）。

### 6.3 域随机化（DR）

RoboTwin 支持 5 轴：杂物、光照、背景、桌面高度、语言。
建议分两档：

- **轻 DR**：背景 + 光照 + 桌面高度小幅扰动，用于主训练；
- **强 DR**：再加杂物 + crazy light，用于鲁棒性测试（OOD）。

### 6.4 数据校验清单

- [ ] `decode_image_bit` 解码后颜色正确（不要二次 BGR→RGB）；
- [ ] 三个相机（head / left_wrist / right_wrist）齐全；
- [ ] 动作维度 14（aloha-agilex），state/action 对齐；
- [ ] 每条 episode 有 success 标记、语言指令；
- [ ] 帧率、episode 长度分布合理（无 0 帧/超长）；
- [ ] LeRobot 数据集能随机抽 10 条可视化。

---

## 7. 训练方案

### 7.1 统一约定

- **动作空间**：先用 `joint`（qpos，14 维），与 RoboTwin 默认一致；后续再试 `ee`。
- **图像**：head + 双腕 3 路；ACT/DP 用 240×320，SmolVLA 用 256×256（省显存）。
- **归一化**：按数据集统计量；训练/评估必须用同一份 norm stats。
- **随机种子**：训练 0/1，评估 0/1；所有结果记录 seed。
- **显存监控**：训练时 `nvidia-smi --query-gpu=memory.used --format=csv -l 5` 落日志。

### 7.2 本机配置

| 策略 | batch | 分辨率 | 关键开关 | 预计时长（50 demos） |
| --- | ---: | --- | --- | --- |
| ACT | 8 | 240×320 | 默认 | 1–3h（4050） |
| DP | 1–2 | 240×320 | 降 batch | 3–8h，可能 OOM |
| SmolVLA | 1 + 梯度累积 | 256×256 | 冻结 VLM、只训 expert、bf16、梯度检查点 | 8–15h（5 epoch 可能更久） |

### 7.3 云端配置（参考）

| 策略 | GPU | batch | 预计 |
| --- | --- | ---: | --- |
| OpenVLA-OFT 7B LoRA | A100 40GB / L40S 48GB | 8–16 | 数小时–1 天 |
| π0.5 LoRA | A100 40GB | 4–8 | 数小时 |

> 具体显存/步数按官方脚本和实际数据量调整；先 1 个任务跑通，再扩多任务。

---

## 8. 评估协议

### 8.1 设置

| 设置 | 训练数据 | 评估环境 | 目的 |
| --- | --- | --- | --- |
| In-distribution | clean | clean | 拟合能力 |
| OOD-1 | clean | randomized（轻 DR） | 视觉/布局泛化 |
| OOD-2 | clean + 轻 DR | randomized（强 DR） | 鲁棒性上限 |

### 8.2 流程

```bash
# 单任务快速评估（先把 all_tasks.yml 的 tasks 裁成 1 个）
bash scripts/eval_policy.sh multitask \
  --config env_cfg/eval/all_tasks.yml \
  --policy-name ACT \
  --ckpt-name <run_name> \
  --env-cfg-type arx_x5 \
  --policy-conda-env <act_env> \
  --eval-env-conda-env robotwin \
  --action-type joint
```

- 冒烟：10–20 episodes / 1 seed；
- 正式：按官方配置跑满（通常每任务 100 episodes，2 seeds；以 `env_cfg/eval` 为准）；
- 每次评估固定：任务、seed、checkpoint、action_type、相机配置；
- 保存视频、逐 episode JSON、成功率、平均 episode 长度。

### 8.3 指标

- **Success Rate**（主指标）；
- 分阶段成功率（抓取/交接/放置，若任务有子目标）；
- 平均完成时间 / episode 长度；
- 推理频率（Hz）与显存峰值；
- OOD 掉点（clean → randomized）。

### 8.4 实验记录

`outputs/results.csv` 字段建议：

```text
date,policy,checkpoint,train_data,eval_task,eval_setting,seed,episodes,success_rate,avg_len,fps,peak_vram_gb,notes
```

`scripts/30_summarize.py` 从 `eval_result/` 自动汇总，避免手抄。

---

## 9. 风险与缓解

| 风险 | 概率 | 影响 | 缓解 |
| --- | --- | --- | --- |
| 6GB 显存 OOM（SmolVLA/DP） | 高 | 中 | 先 ACT；batch=1、256px、冻结 VLM、梯度检查点；不行就上云 |
| 14GB 内存不够（SAPIEN + 策略） | 中 | 高 | 单任务串行、`jobs_per_gpu=1`、加 swap、关桌面应用 |
| 15GB 资产下载 20h+ | 高 | 高 | 镜像 + 多连接 + 夜间下载；或云端下载后同步 |
| Vulkan / SAPIEN 安装失败 | 中 | 高 | 按官方 `_install.sh`；`vulkaninfo` 逐项排查；Docker 需 `NVIDIA_DRIVER_CAPABILITIES=graphics` |
| Python 3.10 vs 3.12 | 高 | 中 | conda 独立环境；本仓库不装 RoboTwin 依赖 |
| 图像颜色/通道错误 | 中 | 高 | 只用 `decode_image_bit`；抽样可视化验收 |
| 评估卡死（A/H/V 系列） | 低 | 中 | RTX 4050 不在名单，但仍先 10 episodes 冒烟 |
| XPolicyLab 数据布局不匹配 | 中 | 中 | M1 做接线 spike，软链/小转换；记录到 runbook |
| 时间被环境问题吞噬 | 高 | 高 | 每个里程碑设时间盒；M0/M1 超过 3 天就考虑云端替代 |

---

## 10. 时间与成本

### 本机（默认路径）

| 阶段 | 内容 | 预计 |
| --- | --- | --- |
| M0 | 环境 + 资产 + 冒烟 | 1 天 + 下载 12–24h |
| M1 | 数据 + 转换 + 校验 | 1 天 |
| M2 | ACT 训练 + 评估 | 1–2 天 |
| M3 | DP（可选） | 1 天 |
| M4 | SmolVLA 6GB | 3–5 天 |
| 合计 |  | **2–3 周**（含下载等待） |

### 云端（可选）

| 项目 | 粗估 |
| --- | --- |
| RTX 4090 24GB | ¥2–4/小时 |
| A100 40GB | ¥6–10/小时 |
| 单轮 VLA 训练 + 评估 | 20–60 小时 → ¥100–600 |
| 存储 | ¥0.5–1/GB/月 |

> 价格为量级参考，按实际云厂商为准。

---

## 11. 下一步（需要你确认）

1. **云端 GPU**：有没有 24GB+ 的云 GPU 可用/可租？决定 M5 是否排进主线。
2. **目标深度**：先「1 个任务跑通闭环」，还是直接「3–5 任务对比」/「冲 50 任务 benchmark」？
3. **数据方式**：先用官方预采集数据，还是必须自己合成域随机化数据？
4. **最终策略**：ACT/DP 基线即可，还是一定要微调 VLA（SmolVLA / OpenVLA-OFT / π0.5）？
5. **网络**：能否开代理/换更快节点？15GB 资产下载是当前最硬的瓶颈。

确认后，我按 M0 → M1 开始落地（先写脚本和 `runbook`，再实际安装/下载）。

---

## 12. 交付物清单

- [ ] `docs/research.md`（已完成）
- [ ] `docs/plan.md`（本文）
- [ ] `docs/runbook.md`（安装/踩坑/命令）
- [ ] `configs/tasks.yaml` + 训练/评估配置
- [ ] `scripts/00–30` 可执行脚本
- [ ] `outputs/results.csv` + 评估视频
- [ ] 一份「本机 6GB 能跑到什么程度」的结论报告
