# 双臂 VLA 仿真：开源生态调研

> 调研时间：2026-10-21
> 目标：在**双臂**仿真环境中完成「数据采集 → 训练 → 仿真评估」闭环，尽量复用成熟开源项目。
> 本机：Ubuntu 24.04 / RTX 4050 Laptop **6GB VRAM** / 14GB RAM / 144GB 可用磁盘 / Clash TUN 网络。

---

## 1. 约束与判断前提

| 维度 | 现状 | 对方案的影响 |
| --- | --- | --- |
| GPU | RTX 4050 Laptop，6GB 显存 | 7B 级 VLA（OpenVLA-OFT）无法本地训练；3B 级 π0 也很勉强 |
| 内存 | 14GB（可用约 9.8GB） | 同时跑「仿真 + 策略 + 数据加载」可能吃紧，只能单任务串行 |
| 磁盘 | 144GB 可用 | 够放 3–5 个任务的 clean/部分 randomized 数据，放不下全量 1.38TB |
| 网络 | Clash TUN fake-IP；HF 实测约 0.1–0.2MB/s/连接 | RoboTwin 资产约 **15GB**，下载是当前最大不确定性 |
| Python | 项目是 3.12（uv） | RoboTwin 要求 **3.10**，必须用 conda 独立环境，不能混装 |
| 系统依赖 | 缺 Vulkan、ffmpeg | SAPIEN 依赖 Vulkan，需要 sudo 安装 |

**结论先行**：本机适合做「**RoboTwin 2.0 + ACT**」的垂直切片（跑通采集→训练→评估），
SmolVLA 可以作为本机进阶目标（需要降分辨率/冻结 VLM），
OpenVLA-OFT / π0.5 这类 3B–7B VLA 建议放到 24GB+ 云 GPU 上训练，再用 XPolicyLab 的分机部署回本地评估。

---

## 2. 推荐技术栈（一句话版）

```text
RoboTwin 2.0  ── 仿真 / 50 个双臂任务 / 数据生成 / 官方评测协议
     │
     ├── XPolicyLab ── 策略服务 + 统一评估（69 个策略适配器，支持 policy server 与仿真分机）
     │
     └── LeRobot ── 数据集格式（v3）+ ACT / DP / SmolVLA 训练与推理
```

- **仿真与数据底座**：RoboTwin 2.0（SAPIEN，14-DoF ALOHA 类双臂，50 任务，10 万+ 轨迹）
- **评估/部署层**：XPolicyLab（RoboTwin 官方已把它作为唯一评估入口）
- **数据/训练层**：LeRobot（RoboTwin 官方提供 HDF5 → LeRobot v2.1/v3.0 转换脚本）
- **本机策略**：ACT（首选）→ Diffusion Policy（可选）→ SmolVLA（6GB 优化后尝试）
- **云端策略**：OpenVLA-OFT（ALOHA 原生，7B）或 π0.5（3B，LeRobot 已集成）

---

## 3. 生态全景

| 项目 | 角色 | 双臂 | 任务/数据 | 评估 | 硬件门槛 | 本机可行性 |
| --- | --- | --- | --- | --- | --- | --- |
| [RoboTwin 2.0](https://github.com/RoboTwin-Platform/RoboTwin) | 仿真 + 数据生成 + benchmark | ✅ ALOHA 类 14-DoF | 50 任务 / 5 本体 / 10 万+ 轨迹 | XPolicyLab | SAPIEN，Vulkan；官方建议 Linux + NVIDIA | ✅（单任务，需 15GB 资产） |
| [XPolicyLab](https://github.com/XPolicyLab/XPolicyLab) | 策略服务 / 统一评估 | ✅（经 RoboTwin） | 69 个策略适配器 | 官方入口 | 自身很轻，随策略而定 | ✅ |
| [LeRobot](https://github.com/huggingface/lerobot) | 数据格式 + 策略库 | ⚠️ 通用（ALOHA 数据格式） | LIBERO / MetaWorld 等 | lerobot-eval | ACT 2–6GB；SmolVLA 10–16GB(BS8) | ✅ ACT / ⚠️ SmolVLA |
| [OpenVLA-OFT](https://github.com/moojink/openvla-oft) | 7B VLA（ALOHA 原生） | ✅ | ALOHA 真机 / LIBERO | 自带 + RoboTwin 适配 | 训练 27–80GB；ALOHA 推理 ~18GB | ❌ 需云端 |
| [openpi / π0](https://github.com/Physical-Intelligence/openpi) | 3B 通用 VLA | ✅（ALOHA/DROID） | 多机器人 | 自带 + XPolicyLab | 训练 24–40GB | ❌ 需云端 |
| [SmolVLA](https://arxiv.org/abs/2506.01844) | 450M 轻量 VLA | ✅（ALOHA 数据） | 社区数据 | LeRobot | 官方 10–16GB(BS8)；可压到 ~6GB | ⚠️ 需调参 |
| [RoboDojo](https://github.com/RoboDojo-Benchmark/RoboDojo) | Isaac Sim 仿真 benchmark | ✅ | 42 仿真 + 18 真机任务 | XPolicyLab | Isaac Sim，24GB+ 更稳 | ❌ 本机不适合 |
| [BiDex-100](https://arxiv.org/abs/2610.25459) | 双臂灵巧手 benchmark（2026-10 新） | ✅ 灵巧手 | 106 任务 / 8,080 遥操作 demo | 统一协议 | 待确认，通常较重 | ⚠️ 关注，暂不作为主线 |
| [ALOHA / ACT](https://tonyzhaozh.github.io/aloha) | 真机双臂 + 模仿学习基线 | ✅ | 真实 ALOHA | 论文协议 | ACT 很轻 | ✅ 仅作算法基线 |

---

## 4. 关键项目拆解

### 4.1 RoboTwin 2.0（主线）

**它提供什么**

- **50 个双臂任务**、**5 种本体**（`aloha-agilex`、`ARX-X5`、`franka-panda`、`piper`、`ur5-wsg`），
  对象库 731 个实例 / 147 个类别。
- **数据生成器**：MLLM 生成任务代码 + 仿真在环修正 + CuRobo 运动规划 + 随机种子搜索，
  一条命令自动合成专家轨迹；支持 5 轴域随机化（杂物、光照、背景、桌面高度、语言）。
- **10 万+ 预采集轨迹**（Hugging Face，压缩包合计约 **1.38TB**）：
  - `demo_clean`：每任务 50 条，单任务压缩包约 **0.2–0.3GB**；
  - `demo_randomized`：每任务 500 条，单任务约 **4–5GB**。
- **官方评测**：`scripts/eval_policy.sh` + XPolicyLab，覆盖 clean / randomized 两种设置，
  有公开 leaderboard。

**数据流（重要）**

```text
下载或自采 → data/<task_config>/<task>/aloha_agilex/data/episode_*.hdf5
           → （可选）XPolicyLab/scripts/transform_lerobot_v30_format.py
           → LeRobot v3 数据集 → 训练 → XPolicyLab policy server → RoboTwin 仿真评估
```

**坑点**

- 要求 **Python 3.10 / CUDA 12.1 / torch 2.4.1 / SAPIEN 3.0.0b1 / numpy 1.26**，与本项目 3.12 冲突，必须独立 conda 环境。
- 需要 **Vulkan**（`libvulkan1`、`mesa-vulkan-drivers`、`vulkan-tools`）和 ffmpeg。
- 资产约 **14.9GB**（背景纹理 10.97GB + 物体 3.74GB + 本体 0.22GB），当前网络下要下很久。
- 图像以 **编码 bit 流**存储，且存在 legacy/standard 两种格式；
  必须用 `XPolicyLab.utils.process_data.decode_image_bit` 解码，**不要**手写 `cv2.imdecode` 后再转 RGB。
- 官方明确建议避免 A/H/V 系列数据中心 GPU 做采集/评估（有卡死问题）；RTX 4050 是 Ada，不在此列，但仍需实测。
- 单任务串行对 14GB 内存友好；不要开多 worker 并行采集。

**为什么选它**：目前双臂「仿真数据 + 统一评测」最完整的开源栈，且 2026 年仍在活跃更新（XPolicyLab、IsaacLab-Arena、RMBench、RoboDojo 互通）。

### 4.2 XPolicyLab（评估层）

- 定位：策略与仿真环境之间的「服务层」，把 N 个策略 × M 个环境从 O(N×M) 降到 O(N+M)。
- 截至 2026-10 集成 **69 个策略**，包括 ACT、DP、OpenVLA-OFT、π0、π0.5、SmolVLA、RDT-1B、GR00T-N1.7 等。
- 关键能力：
  - **policy server / env client 分离**（websocket），支持分机部署；
  - 统一 observation/action 格式（`vision.cam_head`、`state.left_arm_joint_state` 等）；
  - `EVAL_ENV_TYPE=debug` 可无仿真做接线检查；
  - RoboTwin 官方评测入口：`bash scripts/eval_policy.sh multitask ... --env-cfg-type arx_x5`。
- **对本机的价值**：6GB 显卡上如果「仿真 + 策略」同时放不下，可以把策略 server 放到云端，本地只跑仿真客户端。

**注意**：XPolicyLab 很新，适配器质量参差；数据目录约定（`data/<bench_name>/<ckpt_name>/<env_cfg_type>`）与 RoboTwin 原生目录不同，
需要一次「接线 spike」确认软链/转换方式，不能假设命令开箱即用。

### 4.3 LeRobot（数据与训练层）

- **LeRobotDataset v3**：Parquet（state/action）+ MP4（视频），HF Hub 托管；支持流式加载、切片、合并。
- 策略：ACT、Diffusion、VQ-BeT、SmolVLA、π0/π0.5/π0-Fast、GR00T N1.7、XVLA 等。
- 官方 [Compute HW Guide](https://huggingface.co/docs/lerobot/hardware_guide) 给的训练显存（BS=8, AdamW）：

  | 组别 | 策略 | 峰值显存 | 适合 GPU |
  | --- | --- | ---: | --- |
  | Light BC | ACT / VQ-BeT / TDMPC | ~2–6GB | 笔记本 GPU |
  | Diffusion | Diffusion / MultiTask DiT | ~8–14GB | RTX 4070+ |
  | Small VLA | SmolVLA | ~10–16GB | RTX 4080+ |
  | Large VLA | π0 / π0.5 / XVLA | ~24–40GB | A100 40GB+ |

- RoboTwin 官方提供 `transform_lerobot_v21_format.py` / `transform_lerobot_v30_format.py`，直接产出 LeRobot 数据集。
- **不要**用 LeRobot 的 LIBERO/MetaWorld 评估来代表双臂能力；双臂评估走 RoboTwin + XPolicyLab。

### 4.4 OpenVLA-OFT（7B，云端候选）

- 7B Llama-2 + 连续动作头 + action chunking + 多相机 + proprio，ALOHA 上可到 ~50Hz。
- 官方系统要求：**训练 1–8 卡 27–80GB**；ALOHA 任务推理 **~18GB**。
- RoboTwin 文档有专门的 `OpenVLA-oft` 页面和 `preprocess_aloha.sh` / `finetune_aloha.sh` / `eval.sh`。
- 适合「已经有 24–48GB 云端 GPU」时作为**双臂 VLA 主实验**；本机 6GB 只能做数据/评估侧。

### 4.5 π0 / openpi（3B，云端候选）

- 3B flow-matching VLA，openpi 开源，支持 ALOHA、DROID 等；LoRA 微调通常要 24–40GB。
- XPolicyLab 有 `Pi_0` / `Pi_05` 适配器；LeRobot 也原生集成了 π0/π0.5。
- 相比 OpenVLA-OFT，π0.5 更偏通用/跨本体；如果目标是「双臂 + 语言泛化」，值得作为第二组云端实验。

### 4.6 SmolVLA（450M，本机进阶）

- 450M：冻结的 SmolVLM 视觉语言主干 + 轻量 action expert；异步推理；LeRobot 原生。
- 默认配置：`chunk_size=50`、`resize_imgs_with_padding=(512,512)`、`freeze_vision_encoder=True`、`train_expert_only=True`。
- **6GB 可行性**：官方 10–16GB 是 BS=8 的数字；只训练 action expert + batch 1 + 256×256 + 梯度检查点，
  有机会压到 5–7GB，但**必须实测**，且训练时间会明显拉长。

### 4.7 其他值得知道的

- **RoboDojo**：Isaac Sim 上的 42 仿真 + 18 真机任务，eval-only，和 XPolicyLab 共用策略层；
  仿真更逼真但资源门槛高，本机不适合，云端可考虑。
- **BiDex-100**（2026-10 新）：106 个双臂灵巧手任务、8,080 条遥操作 demo、625 万帧；
  如果后续要做**灵巧手/遥操作数据**，是很好的参考，但成熟度和硬件要求还需评估。
- **ALOHA / ACT / Diffusion Policy**：ACT 是双臂模仿学习最稳的基线（80M 级，本机可训）；
  DP 视觉泛化更好但更吃显存。二者都是「基线」，不是 VLA。

---

## 5. 与本机约束的匹配分析

### 5.1 显存账本（训练）

| 策略 | 参数量 | 官方/经验训练显存 | 6GB 本机 | 建议 |
| --- | ---: | ---: | --- | --- |
| ACT | ~80M | 2–6GB (BS8) | ✅ | 首选，先跑通 |
| Diffusion Policy | ~100M | 8–14GB (BS8) | ⚠️ | BS1–2 + 240×320 可试 |
| SmolVLA | 450M | 10–16GB (BS8) | ⚠️ | BS1 + 256px + 冻结 VLM |
| OpenVLA-OFT | 7B | 27–80GB | ❌ | 云端 24–48GB |
| π0 / π0.5 | 3B | 24–40GB | ❌ | 云端 A100 40GB+ |

> 注意：训练显存不只取决于参数量，还取决于 batch、图像分辨率、相机数、优化器状态。
> LeRobot 默认 AdamW 的优化器状态会让显存比「前向+反向」再高 30–100%。

### 5.2 内存与磁盘

- **内存 14GB**：RoboTwin 单环境 + CuRobo + Python 大致能跑，但「仿真 + 策略 server + 数据加载」同时开容易触发 swap；
  建议 `jobs_per_gpu=1`、`clear_cache_freq=1`、关闭桌面应用，必要时加 swap（需要 sudo）。
- **磁盘 144GB**：建议预算
  - 资产 15GB；
  - 3–5 个任务 clean 数据 1–2GB；
  - 1–2 个任务 randomized 子集（每任务 100 条）2–4GB；
  - LeRobot 转换副本 2–5GB；
  - checkpoint / 视频 / 日志 10–20GB。
  合计 < 50GB，安全。

### 5.3 网络（当前最大风险）

实测（2026-10-21）：

- `huggingface.co` 直连下载：约 **0.1MB/s**；
- `hf-mirror.com`：约 **0.2MB/s/连接**（多连接可叠加，需实测）；
- Git clone 可能因 sideband 断连失败，可改用 `codeload.github.com` tarball；
- DNS 返回 Clash fake-IP（198.18.x），**IPv6 路径会卡住**，下载时需 `curl -4` 或设置 `HF_ENDPOINT=https://hf-mirror.com`。

按 0.2MB/s 估算：

| 内容 | 大小 | 预计耗时 |
| --- | ---: | ---: |
| 单任务 clean 50 条 | ~0.25GB | ~20–40 分钟 |
| RoboTwin 资产 | ~15GB | **~20 小时+** |
| 单任务 randomized 500 条 | ~4.5GB | ~6 小时+ |

**这意味着 M0 的资产下载应放到夜间/后台，或者换更快代理/云端预下载。**
如果能在云端（数据中心带宽）下载并打包，再内网/对象存储传回，通常更快。

---

## 6. 选型结论

**主线**：RoboTwin 2.0（仿真/数据/评测协议）+ XPolicyLab（策略服务/评估）+ LeRobot（数据格式/训练）。

理由：

1. 三者已经被官方打通：RoboTwin 内置 XPolicyLab 子模块，官方提供 LeRobot 转换脚本和评估入口。
2. 双臂任务、ALOHA 类 14-DoF 动作空间、clean/randomized 两套评测，和「双臂 VLA」目标完全对齐。
3. 本机 6GB 可以先跑 ACT 闭环；VLA 部分用 SmolVLA 做本机验证，7B/3B 放云端，路径清晰。
4. 不需要自己写仿真器、数据格式或评估协议，符合「尽可能复用开源」的要求。

**不选**：

- RoboDojo（Isaac Sim，本机 6GB/14GB 不现实）；
- 纯 LeRobot LIBERO（单臂，不能代表双臂）；
- 从零自研仿真/数据管线（成本高、无对比基线）。

---

## 7. 参考链接

- RoboTwin 2.0：<https://github.com/RoboTwin-Platform/RoboTwin> · [文档](https://robotwin-platform.github.io/doc/) · [论文](https://arxiv.org/abs/2506.18088) · [数据](https://huggingface.co/datasets/TianxingChen/RoboTwin2.0)
- XPolicyLab：<https://github.com/XPolicyLab/XPolicyLab> · [论文](https://arxiv.org/abs/2608.09892)
- LeRobot：<https://github.com/huggingface/lerobot> · [文档](https://huggingface.co/docs/lerobot) · [硬件指南](https://huggingface.co/docs/lerobot/hardware_guide)
- OpenVLA-OFT：<https://github.com/moojink/openvla-oft> · [论文](https://arxiv.org/abs/2502.19645)
- openpi：<https://github.com/Physical-Intelligence/openpi>
- SmolVLA：<https://arxiv.org/abs/2506.01844>
- RoboDojo：<https://github.com/RoboDojo-Benchmark/RoboDojo>
- BiDex-100：<https://arxiv.org/abs/2610.25459>
- ALOHA / ACT：<https://tonyzhaozh.github.io/aloha> · [论文](https://arxiv.org/abs/2304.13705)
- Diffusion Policy：<https://arxiv.org/abs/2303.04137>
- RoboTwin Leaderboard：<https://robotwin-platform.github.io/leaderboard>
