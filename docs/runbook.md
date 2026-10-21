# Runbook：本机 RTX 4050 跑通 `handover_block`

> 目标：不依赖 5090，先用本机 6GB 跑通「自采仿真数据 → ACT 基线 → 评估」的垂直切片。
> 5090 的差异见文末；当前所有版本以本机为准。

## 0. 当前进度（2026-10-21）

- [x] uv Python 3.10 环境（`envs/robotwin`）
- [x] RoboTwin `ea8b211` + XPolicyLab `fa431ec` 子模块
- [x] 资产 `objects` + `embodiments`（约 9GB，未下 11GB 纹理）
- [x] SAPIEN / mplib 补丁
- [x] 项目内 CUDA 12.4 toolkit（`.cuda` + `.cuda_home`）
- [x] CuRobo v0.7.8 编译（sm_89，5 个扩展）
- [x] SAPIEN 光追冒烟（`Render Well`）
- [x] 采集 1 条 `handover_block` episode（285 帧，HDF5 + 视频 + 指令）
- [x] ACT 预处理 1 条（action 14 维，3 相机 640×480）
- [ ] 采集 50 条 clean（进行中）
- [ ] ACT 训练 + 评估

## 1. 版本矩阵

| 组件 | 版本 / commit | 位置 |
| --- | --- | --- |
| Python | 3.10.22（uv 管理） | `envs/robotwin/.venv` |
| PyTorch | 2.4.1+cu121 | venv |
| SAPIEN | 3.0.0b1 | venv |
| RoboTwin | `ea8b21121ebb3cd201ff5b3fe361944ac94eda3f` | `third_party/RoboTwin` |
| XPolicyLab | `fa431ecd893ee706883e64fe5fe1464ec8cd928d` | `third_party/RoboTwin/XPolicyLab` |
| CuRobo | `v0.7.8` | `third_party/RoboTwin/envs/curobo` |
| CUDA toolkit（编译用） | 12.4.131 | `envs/robotwin/.cuda` |

## 2. 为什么本机可以跑

- 本机是 RTX 4050 Laptop（Ada，sm_89），PyTorch 2.4.1+cu121 原生支持；
- 6GB 显存跑单个 SAPIEN 场景 + CuRobo 规划通常够用，但要单任务串行；
- 14GB 内存偏紧：不要并行采集，`jobs_per_gpu=1`，必要时加 swap。

## 3. 一键检查

```bash
bash scripts/00_check_env.sh
```

## 4. 数据采集（自采，不使用官方预采集数据）

```bash
# 先采 1 条验证管线
EPISODES=1 bash scripts/03_collect_data.sh handover_block demo_clean 1

# 管线通过后采 50 条
EPISODES=50 bash scripts/03_collect_data.sh handover_block demo_clean 50
```

产物：

```text
third_party/RoboTwin/data/demo_clean/handover_block/aloha_agilex/
├── data/episode_0000000.hdf5 ...
├── videos/
└── seed.txt
```

要点：

- `handover_block`：左臂抓红色长条 → 交给右臂 → 放到蓝色垫；成功判定是盒子 xy 误差 <3cm、z 误差 <1cm、右夹爪张开。
- 官方数据生成成功率（aloha-agilex）约 83%；50 条成功轨迹通常需要多探索若干 seed。
- `demo_clean` 不做背景/光照/杂物随机化，不需要 11GB 纹理资产。

## 5. ACT 基线

```bash
# 1) 建立 XPolicyLab 需要的目录映射
bash scripts/04_prepare_act.sh handover_block demo_clean

# 2) 训练（6000 steps，单卡）
bash scripts/05_train_act.sh handover_block 0 0

# 3) 评估（待验证：XPolicyLab server 默认 conda activate，需要 uv 适配）
bash scripts/06_eval_act.sh handover_block demo_clean
```

## 6. 5090 差异（后续迁移）

| 项 | 本机 4050 | 5090 32GB |
| --- | --- | --- |
| 架构 | sm_89 | sm_120（Blackwell） |
| PyTorch | 2.4.1+cu121 | 2.7.1+cu128（或更新） |
| CUDA toolkit | 12.4 | 12.8 |
| `TORCH_CUDA_ARCH_LIST` | `8.9` | `12.0` |
| CuRobo | v0.7.8，需 arch 覆盖 | 同上 + `12.0`；或新版 NVRTC |
| SAPIEN OIDN | 2.0.1 可用 | 需替换 OIDN 2.3.3 并改 `_oidn_tricks.py` |

5090 上建议单独建 `envs/robotwin-5090`，不要改本机 lock；OIDN 补丁参考
[RoboTwin issue #52](https://github.com/RoboTwin-Platform/RoboTwin/issues/52)。

## 7. 已知坑

- 不要手写 `cv2.imdecode` 解码 RoboTwin 图像；统一用 `XPolicyLab.utils.process_data.decode_image_bit`。
- `mplib` 的 `screw plan` 需要去掉 `or collide`（已 patch）。
- SAPIEN `urdf_loader.py` 的编码/`.srdf` 路径补丁（已 patch）。
- 下载走 `HF_ENDPOINT=https://hf-mirror.com`，并加 `curl -4`；本机 DNS 是 Clash fake-IP，IPv6 会卡。
- `data/`、`outputs/`、`third_party/` 均不提交；实验产物只保留索引和汇总。
