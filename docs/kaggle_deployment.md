# Kaggle 部署评估与训练-only Runbook

> 结论先行：**完整的 RoboTwin「仿真采集 → 训练 → 仿真评估」闭环不能在 Kaggle 上跑通。**
> 原因不是显存，而是 Kaggle 容器**没有可用的 NVIDIA Vulkan ICD**；SAPIEN 的 RT 渲染
> 只能落到 llvmpipe 软件光栅器，无法做官方协议的数据采集与评估。
>
> 本文件给出三件事：
> 1. 一个 2 分钟就能验证结论的 probe；
> 2. **Kaggle 唯一可行的角色：训练-only**（数据在支持 Vulkan 的机器上采集，上传到 Kaggle 训练）；
> 3. 完整闭环应该放在哪类机器上跑。

---

## 1. 为什么不能完整跑

RoboTwin 的仿真与数据采集依赖：

- **SAPIEN 3** → Vulkan；
- **RT 光追 + OIDN 去噪** → NVIDIA RTX；
- **CuRobo** → CUDA。

Kaggle GPU 容器通常只提供 CUDA 运行时，不提供 NVIDIA 的 Vulkan ICD。第三方 probe
（2026 年记录）在 Kaggle 上的结论是：

> 镜像只带 intel / lvp / radeon / virtio 的 Vulkan manifest，唯一设备是 **llvmpipe**；
> 手动安装 `libnvidia-gl-580` 虽然会放入 `nvidia_icd.json`，但 `vulkaninfo` 反而枚举到
> **0 个设备**（连 llvmpipe 都没了），说明发行版 ICD 与 Kaggle 注入的容器驱动不匹配。
> 这是结构性问题，不是某次抽到 P100/T4 的运气问题。

参考：[CrispASR Kaggle Vulkan probe commit](https://github.com/CrispStrobe/CrispASR/commit/a3f2d60f628bd7d72a2ab6fe5ae722b8e8756d67)

即使 Vulkan 可用，Kaggle 的其它限制也会让完整闭环很难：

| 限制 | 影响 |
| --- | --- |
| GPU 约 16GB（T4 / P100） | 单条采集可以，但 640×480 正式训练/评估会非常慢 |
| 单次会话约 9 小时 | 采集 + 6000 epoch + 100 episodes 很难一次跑完 |
| `/kaggle/working` 约 20GB | 640×480 预处理 50 条约 **37GB**，放不下；只能用 320×240（约 9.1GB） |
| 无持久化磁盘 | 会话结束未 Save Version 就丢失 |
| Internet 默认关闭 | 需要手动打开才能 clone/下载 |

> 结论：**不要把 Kaggle 当作 RoboTwin 的仿真主机**。Kaggle 适合做「训练-only」，
> 或者做数据统计/预处理/分析。

---

## 2. 先跑 2 分钟 Probe（推荐）

在 Kaggle Notebook 里新建一个 cell，开启 **Internet**，选 **GPU T4 x2**，运行：

```python
import glob, subprocess, os

print("=== nvidia-smi ===")
print(subprocess.run(["nvidia-smi"], capture_output=True, text=True).stdout[:2000])

print("=== Vulkan ICD ===")
print(glob.glob("/usr/share/vulkan/icd.d/*"))

print("=== vulkaninfo ===")
r = subprocess.run(["vulkaninfo", "--summary"], capture_output=True, text=True)
print(r.stdout[:4000])
print(r.stderr[:1000])
```

如果 `vulkaninfo` 不存在：

```bash
!apt-get update -qq && apt-get install -y -qq vulkan-tools libvulkan1
```

期望结果（也就是当前已知情况）：

- `/usr/share/vulkan/icd.d/` 里没有 `nvidia_icd.json`；
- `vulkaninfo` 只看到 `llvmpipe`（软件设备），没有 `NVIDIA T4/P100`。

**如果你真的看到了 NVIDIA Vulkan 设备**，说明 Kaggle 环境发生了变化，可以重新评估
完整闭环；否则直接进入训练-only 方案，不要在 Kaggle 上尝试安装 `libnvidia-gl-*`
或编译 SAPIEN，浪费 GPU 配额。

---

## 3. Kaggle 规格（以当前 UI 为准）

| 项 | 大致情况 |
| --- | --- |
| GPU | T4 ×2（16GB/卡）或 P100（16GB） |
| RAM / CPU | 约 29GB / 4 vCPU（GPU notebook） |
| 单次运行 | 约 9 小时（GPU） |
| 工作磁盘 | 约 20GB（`/kaggle/working`） |
| GPU 配额 | 约 30 小时/周 |
| Internet | Notebook 设置里手动开启 |

Kaggle 版本/配额会变，以上只用于估算；以 Notebook 右上角 Settings 和 Kaggle 文档为准。

---

## 4. 推荐架构：采集/评估在 host，训练在 Kaggle

```text
┌──────────────────────────────┐        ┌──────────────────────────┐
│ Vulkan-capable host           │        │ Kaggle GPU (T4/P100)      │
│ 5090 / 云 VM（graphics 驱动） │        │ 只做 ACT 训练             │
│                              │        │                          │
│ 1. RoboTwin 自采 50 条 clean  │        │ 4. 读取 raw HDF5          │
│ 2. 导出 raw HDF5（812MB）     │───────▶│ 5. 预处理 320×240（9.1GB）│
│ 3. 上传 Kaggle Dataset        │        │ 6. ACT 6000 epoch         │
│                              │◀───────│ 7. 下载 checkpoint（321MB）│
│ 8. GPU policy + SAPIEN 评估   │        │                          │
│ 9. 100 episodes clean/random  │        └──────────────────────────┘
└──────────────────────────────┘
```

- **采集必须**在支持 NVIDIA Vulkan/RTX 的机器上（本机 4050 已验证；5090/云 VM 更快）。
- **训练可以**在 Kaggle 完成；训练代码不需要 SAPIEN/Vulkan。
- **评估必须**回到 host；Kaggle 无法跑 SAPIEN 仿真。

完整 host 闭环见 [cloud_server_runbook.md](./cloud_server_runbook.md)；本文只写 Kaggle 训练段。

---

## 5. 在 host 准备 Kaggle Dataset（raw HDF5）

在已经采集完 50 条的 host 上：

```bash
cd dual_arm_VLA/third_party/RoboTwin/data/demo_clean/handover_block/aloha_agilex
zip -r handover_raw.zip data
# 约 812MB；只包含 HDF5，不需要视频/纹理
```

到 Kaggle → **Datasets → New Dataset**，上传 `handover_raw.zip`，命名为
`handover-raw`（private 即可）。训练 notebook 里会挂到：

```text
/kaggle/input/handover-raw/data/episode_0000000.hdf5 ...
```

> 也可以把 9.1GB 的 `processed_data` 直接做成 Dataset，省去 Kaggle 端预处理；
> 但 raw 812MB 上传更快，且预处理在 Kaggle 上只需约 30 秒，推荐 raw。

---

## 6. Kaggle Notebook：训练-only 步骤

### 6.1 Notebook 设置

- Accelerator：**GPU T4 x2**（T4 对 torch 2.4.1 兼容性最好；P100 请先用
  `torch.cuda.get_arch_list()` 确认有 sm_60）；
- Internet：**On**；
- 持久化：训练结束后 **Save Version**，只保留 checkpoint/日志。

### 6.2 Cell 1：clone 代码（不下载资产）

```bash
%cd /kaggle/working
!git clone <YOUR_GITHUB_REPO_URL> dual_arm_VLA
%cd dual_arm_VLA

!git clone https://github.com/RoboTwin-Platform/RoboTwin.git third_party/RoboTwin
!git -C third_party/RoboTwin checkout ea8b21121ebb3cd201ff5b3fe361944ac94eda3f
!git -C third_party/RoboTwin submodule update --init --recursive

# 不需要 assets / textures / CuRobo，训练不依赖它们
```

### 6.3 Cell 2：uv 环境

```bash
!curl -LsSf https://astral.sh/uv/install.sh | sh
!$HOME/.local/bin/uv python install 3.10
!$HOME/.local/bin/uv sync --project envs/robotwin --no-cache

!$HOME/.local/bin/uv pip install --python envs/robotwin/.venv/bin/python \
  -e third_party/RoboTwin/XPolicyLab

# 只为了拿到 ACT_BATCH_SIZE / ACT_NUM_EPOCHS / ACT_SAVE_FREQ 等补丁
!envs/robotwin/.venv/bin/python scripts/patches/apply_upstream_patches.py
```

说明：

- 这一步会安装 torch 2.4.1+cu121、h5py、opencv、sapien 等；**不会初始化 Vulkan**；
- `apply_upstream_patches.py` 只改文件，不跑仿真；
- 如果磁盘紧张，可删掉 `third_party/RoboTwin/.git` 和 `XPolicyLab/.git`（不影响训练）。

### 6.4 Cell 3：挂载 raw 数据并预处理 320×240

```bash
!mkdir -p third_party/RoboTwin/data/demo_clean/handover_block/aloha_agilex
!cp -r /kaggle/input/handover-raw/data \
  third_party/RoboTwin/data/demo_clean/handover_block/aloha_agilex/

!ACT_IMAGE_W=320 ACT_IMAGE_H=240 \
  bash scripts/04_prepare_act.sh handover_block demo_clean
```

- 预处理产物约 **9.1GB**，位于
  `third_party/RoboTwin/XPolicyLab/policy/ACT/processed_data/...`；
- Kaggle 20GB 工作盘下，`.venv`（约 7.8GB）+ 9.1GB + raw 0.8GB ≈ 17.7GB，能放下；
- **不要用 640×480**：50 条约 37GB，Kaggle 放不下。

### 6.5 Cell 4：训练 6000 epoch

```bash
!EPOCHS=6000 BATCH_SIZE=8 SAVE_FREQ=1000 \
  bash scripts/05_train_act.sh handover_block 0 0
```

- T4 16GB、320×240、batch 8；6000 epoch 约 3–6 小时（以实际为准）；
- checkpoint 在
  `third_party/RoboTwin/XPolicyLab/policy/ACT/checkpoints/RoboTwin-handover_block-arx_x5-joint-0/`；
- 日志在 `outputs/logs/act_train_*.log`；
- ACT 不支持断点续训；9 小时会话要留足时间，超时会丢未 Save 的 checkpoint。

### 6.6 Cell 5：保存 checkpoint（Save Version 前清理）

```bash
!mkdir -p /kaggle/working/out
!cp third_party/RoboTwin/XPolicyLab/policy/ACT/checkpoints/RoboTwin-handover_block-arx_x5-joint-0/policy_epoch_6000_seed_0.ckpt /kaggle/working/out/
!cp third_party/RoboTwin/XPolicyLab/policy/ACT/checkpoints/RoboTwin-handover_block-arx_x5-joint-0/dataset_stats.pkl /kaggle/working/out/
!cp -r outputs/logs /kaggle/working/out/

# 释放 9.1GB，避免 Save Version 输出过大
!rm -rf third_party/RoboTwin/XPolicyLab/policy/ACT/processed_data
```

然后 **Save Version**，从 Notebook 输出下载 `policy_epoch_6000_seed_0.ckpt`。

---

## 7. 回到 host 做正式评估

把 checkpoint 放到 host 的 ACT checkpoint 目录：

```bash
# host 上
cp policy_epoch_6000_seed_0.ckpt \
  third_party/RoboTwin/XPolicyLab/policy/ACT/checkpoints/RoboTwin-handover_block-arx_x5-joint-0/
```

评估必须与训练同分辨率（Kaggle 是 320×240）：

```bash
export ACT_IMAGE_W=320 ACT_IMAGE_H=240
export ACT_DEVICE=cuda:0 EXPERT_CHECK=1

RUN=RoboTwin-handover_block-arx_x5-joint-0
bash scripts/06_eval_act.sh handover_block demo_clean 0 "$RUN" 100
bash scripts/06_eval_act.sh handover_block demo_randomized 0 "$RUN" 100
```

- host 需要 NVIDIA Vulkan/RTX（本机 4050 / 5090 / 云 VM with graphics）；
- 320×240 的模型不能直接按 640×480 评估，必须保持 `ACT_IMAGE_W/H` 一致；
- randomized 评估需要 `background_texture` 资产（见 cloud runbook）。

---

## 8. 为什么是 320×240 / batch 8

| 项 | 640×480 | 320×240 |
| --- | --- | --- |
| 50 条预处理 | 约 37GB | **约 9.1GB** |
| T4 训练 | 很慢，可能 OOM | 可行，batch 8 |
| Kaggle 20GB 工作盘 | 放不下 | 能放下 |
| 与原始相机分辨率 | 上采样 | **原生分辨率** |

RoboTwin 相机原始输出就是 320×240；640×480 是 ACT 官方预处理的上采样。
Kaggle 训练用 320×240 是工程折中，正式 host 评估必须用同一个尺寸。

---

## 9. 替代方案（如果你坚持要“完整闭环”）

| 方案 | 采集 | 训练 | 评估 | 说明 |
| --- | --- | --- | --- | --- |
| **本机 4050** | ✅ | ⚠️ 慢 | ⚠️ 仅 CPU policy（约 5min/ep） | 已验证，适合 smoke |
| **5090 工作站** | ✅ | ✅ | ✅ 32GB 可 GPU policy | 推荐正式闭环 |
| **云 VM（完整 NVIDIA 驱动 + graphics）** | ✅ | ✅ | ✅ | 参考 cloud_server_runbook.md；Docker 加 `NVIDIA_DRIVER_CAPABILITIES=graphics` |
| **Kaggle** | ❌ 无 Vulkan ICD | ✅ 训练-only | ❌ 无 Vulkan | 本文 |
| **Colab / 其它免费 notebook** | 先用 probe 验证 | 可能 | 可能 | 不要假设有 NVIDIA Vulkan ICD |

> 如果你能接受「数据在 5090 采集、Kaggle 训练、5090 评估」，本文的 5–7 节就是可执行方案。
> 如果要求「采集也在 Kaggle」，当前不可行。

---

## 10. 验收清单（Kaggle 训练段）

- [ ] Probe 确认无 NVIDIA Vulkan 设备（预期）
- [ ] Kaggle Dataset `handover-raw` 已上传（812MB）
- [ ] Cell 2 `uv sync` 成功，`torch.cuda.is_available()` 为 True
- [ ] `04_prepare_act.sh` 产出 50 条、action 14、320×240
- [ ] `05_train_act.sh` 到 6000 epoch，checkpoint 存在
- [ ] **Save Version** 输出包含 `policy_epoch_6000_seed_0.ckpt`
- [ ] host 上 320×240 评估 100 episodes 完成
- [ ] `docs/results/` 有 `_result.txt` 与 CSV 快照

---

## 11. 参考

- 第三方 Kaggle Vulkan probe（结论：无 NVIDIA ICD）：
  <https://github.com/CrispStrobe/CrispASR/commit/a3f2d60f628bd7d72a2ab6fe5ae722b8e8756d67>
- Kaggle Notebooks 文档：<https://www.kaggle.com/docs/notebooks>
- Kaggle GPU 使用建议：<https://www.kaggle.com/docs/efficient-gpu-usage>
- 完整 host 闭环：[cloud_server_runbook.md](./cloud_server_runbook.md)
- 本机验证记录：[baseline_report.md](./baseline_report.md)
