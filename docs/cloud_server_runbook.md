# 云服务器正式闭环 Runbook

> 目标：在**全新云服务器**上克隆本仓库，完成 `handover_block` 的
> **自采 50 条 clean 数据 → ACT 6000 epoch → clean / randomized 各 100 episodes 评估**。
>
> 本机 RTX 4050 已经验证过环境、采集、训练、评估链路；本文件里的 5090（Blackwell）分支
> 来自 RoboTwin 官方 issue 与本机梳理，**尚未在 5090 实跑**，执行时请以实际报错为准。
>
> 仓库不包含以下内容（都已被 `.gitignore` 忽略），必须在新机器上重新生成：
> `third_party/`、`data/`、`assets/`、`outputs/`、`*.hdf5`、`*.mp4`、checkpoint、虚拟环境。

---

## 1. 机器要求

| 项 | 建议 |
| --- | --- |
| OS | Ubuntu 22.04 / 24.04，x86_64 |
| GPU | 24GB+ 显存；**32GB 5090 / A100 40GB / L40S 48GB** 最稳 |
| 驱动 | NVIDIA Driver ≥ 550；5090 建议 ≥ 570/580 |
| 内存 | 32GB+（本机 14GB 偏紧） |
| 磁盘 | 100GB+ 可用（640×480 预处理后约 37GB） |
| 权限 | sudo（装 Vulkan/ffmpeg） |
| 网络 | 能访问 GitHub + Hugging Face；国内建议 `HF_ENDPOINT=https://hf-mirror.com` |

先确认 GPU 架构：

```bash
nvidia-smi --query-gpu=name,memory.total,driver_version,compute_cap --format=csv
df -h
free -h
```

- `compute_cap` **8.0 / 8.6 / 8.9**（A100 / A10 / 4090 / L40S）→ 走 **Track A**，当前 lock（torch 2.4.1+cu121）可用。
- `compute_cap` **12.0**（RTX 5090）→ 走 **Track B**，必须换 torch 2.7.1+cu128 / CUDA 12.8。
- H100（9.0）也能跑 torch 2.4.1，但 RoboTwin 官方提示 A/H 系列偶发卡死，优先 A/Ada。

> Docker：必须加 `--gpus all -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics`，
> 缺 `graphics` 会导致 SAPIEN/Vulkan 段错误。

---

## 2. 系统依赖

```bash
sudo apt update
sudo apt install -y \
  build-essential git curl wget unzip tmux \
  ffmpeg libvulkan1 mesa-vulkan-drivers vulkan-tools \
  libgl1 libglib2.0-0

# 检查 Vulkan（应看到 NVIDIA GPU）
vulkaninfo --summary | head -30
ffmpeg -version | head -1
```

如果 `vulkaninfo` 看不到 NVIDIA：

```bash
ls /usr/share/vulkan/icd.d/nvidia_icd.json
ldconfig -p | grep libvulkan.so.1
```

> 云服务器通常没有 X11。RoboTwin 的采集/评估使用 SAPIEN 离屏渲染，正常不需要 `DISPLAY`；
> 如果容器里报 Vulkan/display 错误，优先检查 `NVIDIA_DRIVER_CAPABILITIES=graphics` 和 ICD。

安装 `uv`（本项目所有 Python 环境用 uv 管理）：

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.local/bin/env 2>/dev/null || export PATH="$HOME/.local/bin:$PATH"
uv --version
```

安装 Miniconda（只用于给 CuRobo 编译提供**项目内 CUDA toolkit**，不是 Python 主环境）：

```bash
curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/miniconda.sh
bash /tmp/miniconda.sh -b -p "$HOME/miniconda3"
source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda --version
```

---

## 3. 克隆仓库与上游代码

```bash
export WORK="$HOME/work"
mkdir -p "$WORK"
cd "$WORK"

git clone <YOUR_GITHUB_REPO_URL> dual_arm_VLA
cd dual_arm_VLA

# RoboTwin 不在仓库里，单独 clone 并固定 commit
mkdir -p third_party
git clone https://github.com/RoboTwin-Platform/RoboTwin.git third_party/RoboTwin
git -C third_party/RoboTwin checkout ea8b21121ebb3cd201ff5b3fe361944ac94eda3f
git -C third_party/RoboTwin submodule update --init --recursive

git -C third_party/RoboTwin rev-parse HEAD
git -C third_party/RoboTwin/XPolicyLab rev-parse HEAD
# 应为 ea8b211... / fa431ec...
```

> 如果 GitHub 慢，可先在能联网的机器下载 tarball/镜像，或给 git 配代理；
> `XPolicyLab` 是 RoboTwin 的子模块，必须执行 `submodule update`。

---

## 4. uv 环境（按 GPU 架构二选一）

### Track A：A100 / 4090 / L40S（sm_80 / 8.6 / 8.9）

```bash
cd "$WORK/dual_arm_VLA"
uv python install 3.10
uv sync --project envs/robotwin

envs/robotwin/.venv/bin/python - <<'PY'
import torch, sapien
print("torch", torch.__version__, "cuda", torch.version.cuda)
print("available", torch.cuda.is_available(), torch.cuda.get_device_name(0))
print("sapien", sapien.__version__)
PY
```

预期：`torch 2.4.1+cu121`、CUDA available、`sapien 3.0.0b1`。

### Track B：RTX 5090（sm_120）

torch 2.4.1 没有 Blackwell 内核，必须换 **torch 2.7.1 + cu128**：

```bash
cd "$WORK/dual_arm_VLA/envs/robotwin"

sed -i 's/"torch==2.4.1"/"torch==2.7.1"/' pyproject.toml
sed -i 's/"torchvision==0.19.1"/"torchvision==0.22.1"/' pyproject.toml

cat >> pyproject.toml <<'EOF'

[[tool.uv.index]]
name = "pytorch-cu128"
url = "https://download.pytorch.org/whl/cu128"
explicit = true

[tool.uv.sources]
torch = { index = "pytorch-cu128" }
torchvision = { index = "pytorch-cu128" }
EOF

rm -f uv.lock
uv lock
uv sync

cd "$WORK/dual_arm_VLA"
envs/robotwin/.venv/bin/python - <<'PY'
import torch
print("torch", torch.__version__, "cuda", torch.version.cuda)
print("cap", torch.cuda.get_device_capability(0))
PY
```

预期：`torch 2.7.1+cu128`、`cap (12, 0)`。

> Track B 修改了 `envs/robotwin/pyproject.toml` / `uv.lock`，只用于这台云机；
> 不建议直接提交回主分支，除非你明确要维护一个 5090 profile。
>
> 结果提交前建议还原，避免把 5090 profile 带进主分支：
>
> ```bash
> git checkout -- envs/robotwin/pyproject.toml envs/robotwin/uv.lock
> ```
>
> 如果确实要长期维护 5090 环境，建议单独开分支提交这两个文件。


---

## 5. 下载资产

先下 **clean 必需**的 objects + embodiments（约 4GB）：

```bash
cd "$WORK/dual_arm_VLA"
export HF_ENDPOINT=https://hf-mirror.com
bash scripts/02_download_assets.sh
```

**正式 randomized 评估**还需要 11GB 背景纹理：

```bash
WITH_TEXTURES=1 bash scripts/02_download_assets.sh
```

检查：

```bash
du -sh third_party/RoboTwin/assets
ls third_party/RoboTwin/assets/objects third_party/RoboTwin/assets/embodiments >/dev/null && echo OK
ls third_party/RoboTwin/assets/background_texture >/dev/null && echo "textures OK"
```

> `02_download_assets.sh` 会解压并运行 `update_embodiment_config_path.py`，
> 把 `${ASSETS_PATH}` 替换成绝对路径；必须在 RoboTwin 根目录执行（脚本已处理）。
>
> 资产必须在下一步 `01_setup` 之前存在，否则 embodiment 配置生成会失败。

---

## 6. 补丁 + CUDA + CuRobo + 自检

### Track A

```bash
cd "$WORK/dual_arm_VLA"
bash scripts/01_setup_robotwin.sh
```

它会依次：

1. `uv sync`（复用已建环境）
2. 应用 SAPIEN / mplib / ACT / XPolicyLab-uv 补丁
3. 安装 `XPolicyLab` editable
4. 生成 embodiment 配置（`*_tmp.yml` → `*.yml`）
5. 用 conda 在 `envs/robotwin/.cuda` 安装 **CUDA 12.4.1**（只用于编译）
6. 编译 **CuRobo v0.7.8**（按当前 GPU 自动设置 `TORCH_CUDA_ARCH_LIST`）
7. 运行 `scripts/00_check_env.sh`

预期最后 `ALL CHECKS PASSED (12)`。

### Track B（5090）

```bash
cd "$WORK/dual_arm_VLA"
CUDA_TOOLKIT_VERSION=12.8.1 bash scripts/01_setup_robotwin.sh
```

然后补 **OIDN 2.3.3**（RoboTwin issue #52 的 50 系 workaround）：

```bash
SAPIEN_SITE="$WORK/dual_arm_VLA/envs/robotwin/.venv/lib/python3.10/site-packages/sapien"
mkdir -p /tmp/oidn && cd /tmp/oidn
wget -q https://github.com/RenderKit/oidn/releases/download/v2.3.3/oidn-2.3.3.x86_64.linux.tar.gz
tar -xzf oidn-2.3.3.x86_64.linux.tar.gz
cp oidn-2.3.3.x86_64.linux/lib/libOpenImageDenoise*.so* "$SAPIEN_SITE/oidn_library/"
sed -i 's/2\.0\.1/2.3.3/g' "$SAPIEN_SITE/_oidn_tricks.py"

cd "$WORK/dual_arm_VLA/third_party/RoboTwin"
CUDA_VISIBLE_DEVICES=0 ../../envs/robotwin/.venv/bin/python scripts/test_render.py
# 预期最后一行: Render Well
```

> 5090 的 CuRobo 编译需要 `TORCH_CUDA_ARCH_LIST=12.0`；`01_setup` 会自动从
> `torch.cuda.get_device_capability()` 取到 `12.0`。
> 如果编译报 `Unknown CUDA arch (10.1)`，说明 torch 还是 2.4.1，回 Track B 重装。
>
> CuRobo v0.7.8 与 torch 2.7 / CUDA 12.8 的 C++ 兼容性未在本机验证；
> 若编译失败，可尝试 NVlabs/curobo 的新版（改用 NVRTC 编译），但需确认 RoboTwin
> 的 `MotionGen` API 兼容；或先在 Track A 机器上验证数据/训练流程，再单独处理 5090 编译。

---

## 7. 正式采集：50 条 clean

```bash
cd "$WORK/dual_arm_VLA"
tmux new -s collect
bash scripts/03_collect_data.sh handover_block demo_clean 50 0
```

- 脚本会把 `env_cfg/task_config/demo_clean.yml` 的 `episode_num` 改成 50；
- 输出在 `third_party/RoboTwin/data/demo_clean/handover_block/aloha_agilex/`；
- 日志在 `outputs/logs/collect_*.log`；
- 专家数据生成成功率约 **83%**，50 条通常需要探索约 60 个 seed。

另开终端检查：

```bash
find third_party/RoboTwin/data/demo_clean/handover_block/aloha_agilex/data -name '*.hdf5' | wc -l
# 50
```

> 中断后重跑同一条命令即可续采（seed 文件会保留）；如果某个 seed 卡死，
> 参考 RoboTwin `data/process_stuck.py` 跳过。
>
> **不需要**采 `demo_randomized` 才能做 randomized 评估；randomized 是评估环境，
> 只需要背景纹理资产。若想做 randomized 训练，再采
> `bash scripts/03_collect_data.sh handover_block demo_randomized 100 0`。

---

## 8. 预处理：640×480

```bash
cd "$WORK/dual_arm_VLA"
export ACT_IMAGE_W=640 ACT_IMAGE_H=480
bash scripts/04_prepare_act.sh handover_block demo_clean
```

产物：

```text
third_party/RoboTwin/XPolicyLab/policy/ACT/processed_data/RoboTwin/handover_block/arx_x5-joint/
```

检查：

```bash
du -sh third_party/RoboTwin/XPolicyLab/policy/ACT/processed_data/RoboTwin/handover_block/arx_x5-joint
# 约 37GB

envs/robotwin/.venv/bin/python scripts/08_stats.py
# episodes=50, action_dim=14, length min/max/mean 约 272/304/282
```

> 640×480 是官方 ACT 设置；本机 6GB 为了速度用了 320×240。
> 如果云机显存 < 24GB，可改用 `ACT_IMAGE_W=320 ACT_IMAGE_H=240`，
> 训练/评估必须保持一致。

---

## 9. 正式训练：ACT 6000 epoch

```bash
cd "$WORK/dual_arm_VLA"
export ACT_IMAGE_W=640 ACT_IMAGE_H=480

EPOCHS=6000 BATCH_SIZE=16 SAVE_FREQ=1000 \
  bash scripts/05_train_act.sh handover_block 0 0
```

- 32GB 建议 batch 16；24GB 用 8；OOM 再降到 4。
- checkpoint 在
  `third_party/RoboTwin/XPolicyLab/policy/ACT/checkpoints/RoboTwin-handover_block-arx_x5-joint-0/`；
- `SAVE_FREQ=1000` 会留下 1000/2000/.../6000 多个 checkpoint，便于比较；
- 4050 上 2000 epoch 约 53 分钟；4090/A100/5090 上 6000 epoch 预计 **30–90 分钟**量级。
- 训练日志：`outputs/logs/act_train_handover_block_seed0_*.log`。
- ACT 没有断点续训；中断需重跑。

---

## 10. 正式评估：clean + randomized，各 100 episodes

先确认 `temporal_agg` 为官方默认（GPU 显存足够时）：

```bash
cd "$WORK/dual_arm_VLA"
sed -i 's/temporal_agg: false/temporal_agg: true/' \
  third_party/RoboTwin/XPolicyLab/policy/ACT/deploy.yml
grep temporal_agg third_party/RoboTwin/XPolicyLab/policy/ACT/deploy.yml
```

然后：

```bash
export ACT_IMAGE_W=640 ACT_IMAGE_H=480
export ACT_DEVICE=cuda:0
export EXPERT_CHECK=1

RUN=RoboTwin-handover_block-arx_x5-joint-0

# clean
bash scripts/06_eval_act.sh handover_block demo_clean 0 "$RUN" 100

# randomized（需要 background_texture 资产）
bash scripts/06_eval_act.sh handover_block demo_randomized 0 "$RUN" 100
```

可选第二个评估 seed：

```bash
bash scripts/06_eval_act.sh handover_block demo_clean 1 "$RUN" 100
bash scripts/06_eval_act.sh handover_block demo_randomized 1 "$RUN" 100
```

结果路径：

```text
third_party/RoboTwin/eval_result/handover_block/ACT/<task_config>/<run>/<timestamp>/
├── _result.txt      # 最后一行的分数，如 0.42
└── episode*.mp4
```

> 如果出现 `RuntimeError: cannot create buffer`：说明 GPU 显存不够同时跑
> policy server + SAPIEN。优先换 32GB 卡；24GB 可尝试
> `ROBOTWIN_DISABLE_DENOISER=1 ROBOTWIN_RT_SAMPLES=8`；仍不行则临时用
> `ACT_DEVICE=cpu`（很慢，仅 smoke）。
>
> 本地 6GB 上 `EXPERT_CHECK=1` 会失败/极慢；云端 24GB+ 用默认 1。

---

## 11. 汇总与提交结果

```bash
cd "$WORK/dual_arm_VLA"
envs/robotwin/.venv/bin/python scripts/07_summarize_eval.py
cat outputs/results.csv

# 只提交小体积结果，不提交 data/outputs/checkpoints
cp outputs/results.csv docs/results/results.csv
find third_party/RoboTwin/eval_result -name '_result.txt' -print

git status --short
git add docs/results docs/experiment_log.md docs/baseline_report.md
git commit -m "results: cloud ACT 6000ep clean/randomized 100ep"
git push
```

同时把云机结果回填到 `docs/experiment_log.md` 的表格（success rate、episodes、seed、显存、耗时）。

---

## 12. 时间与磁盘预算

| 阶段 | 量级 |
| --- | --- |
| 系统 + uv + 资产下载 | 1–2 小时（取决于网络，资产约 15GB） |
| 50 条 clean 采集 | 30–60 分钟 |
| 640×480 预处理 | 1–3 分钟（约 37GB） |
| ACT 6000 epoch | 30–90 分钟（24–48GB 卡） |
| clean 100 episodes | 约 1–2 小时 |
| randomized 100 episodes | 约 1–2 小时 |
| **合计** | **半天到一天** |

磁盘：资产 15GB + 原始数据 1GB + 预处理 37GB + checkpoint 1GB + 视频 2GB ≈ **56GB**；
建议 100GB+ 可用。

---

## 13. 常见问题

| 现象 | 处理 |
| --- | --- |
| `vulkaninfo: command not found` / `import sapien` 报 Vulkan | `sudo apt install vulkan-tools libvulkan1 mesa-vulkan-drivers`；容器加 `NVIDIA_DRIVER_CAPABILITIES=graphics` |
| `nvcc: command not found` | 用 `01_setup` 的 conda CUDA，或设 `CUDA_HOME` 指向系统 CUDA；检查 `.cuda_home/bin/nvcc` |
| CuRobo 编译报 `invalid command 'bdist_wheel'` | `uv pip install --python envs/robotwin/.venv/bin/python wheel` 后重跑 |
| `Unknown CUDA arch (10.1)` / 5090 无 kernel | 换 torch 2.7.1+cu128（Track B）；`TORCH_CUDA_ARCH_LIST=12.0` |
| `OIDN Error: invalid handle` | 5090 按第 6 节替换 OIDN 2.3.3 |
| `cannot create buffer` | GPU 显存不足（policy + sim）；换 32GB / 降 samples / CPU policy |
| HF 下载慢/超时 | `HF_ENDPOINT=https://hf-mirror.com`；失败重跑会断点续传 |
| `git submodule` 空 / 找不到 XPolicyLab | `git -C third_party/RoboTwin submodule update --init --recursive` |
| `assets/objects` 缺失 | 先跑 `scripts/02_download_assets.sh`，再跑 `01_setup` |
| `demo_randomized` 评估失败 | 没有 `background_texture`；`WITH_TEXTURES=1 bash scripts/02_download_assets.sh` |
| `checkpoint` 不存在 | 训练未到 6000 / `SAVE_FREQ` 不匹配；检查 `policy_epoch_6000_seed_0.ckpt` |
| eval 报 conda 相关错误 | 确认 `scripts/patches/apply_upstream_patches.py` 已跑；XPolicyLab 支持 uv venv |
| 训练 OOM | `BATCH_SIZE=8` 或 `4`；640→320（预处理的图像尺寸） |
| 磁盘满 | 删除旧 `processed_data`/`eval_result`；或换更大磁盘 |

---

## 14. 验收清单

- [ ] `make check` → `ALL CHECKS PASSED (12)`
- [ ] `test_render.py` → `Render Well`
- [ ] `find .../data -name '*.hdf5' | wc -l` → **50**
- [ ] `scripts/08_stats.py` → episodes=50，action_dim=14
- [ ] 训练产出 `policy_epoch_6000_seed_0.ckpt`
- [ ] clean 100 episodes 的 `_result.txt`
- [ ] randomized 100 episodes 的 `_result.txt`（有背景纹理）
- [ ] 每条评估有 `episode*.mp4`
- [ ] `outputs/results.csv` 已生成并复制到 `docs/results/`
- [ ] `git status` 只有 docs 变更；`data/outputs/third_party` 未被提交

---

## 15. 一句话流程

```bash
# Track A（4090/A100/L40S）
git clone <REPO> && cd dual_arm_VLA
uv sync --project envs/robotwin
bash scripts/02_download_assets.sh
bash scripts/01_setup_robotwin.sh
bash scripts/03_collect_data.sh handover_block demo_clean 50 0
ACT_IMAGE_W=640 ACT_IMAGE_H=480 bash scripts/04_prepare_act.sh handover_block demo_clean
EPOCHS=6000 BATCH_SIZE=16 SAVE_FREQ=1000 bash scripts/05_train_act.sh handover_block 0 0
ACT_IMAGE_W=640 ACT_IMAGE_H=480 ACT_DEVICE=cuda:0 EXPERT_CHECK=1 \
  bash scripts/06_eval_act.sh handover_block demo_clean 0 RoboTwin-handover_block-arx_x5-joint-0 100
```
