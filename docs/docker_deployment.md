# Docker 部署：RoboTwin + ACT + 宿主机 Clash

## 执行前：替换宿主机安装地址，确认系统盘 / 数据盘

先按[安装路径与磁盘说明](storage_layout.md)确认真实挂载点。下表列出本篇必须设置的位置；
**`/data` 只是示例，替换为自己的数据盘挂载点，没有独立数据盘时用 `$HOME`。**

| 位置 | 本篇需要设置 / 检查什么 |
| --- | --- |
| 宿主机仓库父目录 `WORK` | 下方设为 `$DATA_ROOT/work`；源码、`outputs/docker`、`backups/docker` 跟随仓库 |
| Docker 持久卷地址 | 首次 pull / build / up 前检查 `Docker Root Dir`；需要放数据盘时配置 daemon 的 `data-root` |
| 镜像 / 容器层地址 | 若使用 containerd image store，另查 containerd 的 `root`；它不随 Docker `data-root` 自动移动 |
| `docker/.env` | 编辑本篇第 3 节的网络与镜像参数；当前 Compose 不通过 `DATA_ROOT` 指定持久卷位置 |
| 宿主机 Clash | `CLASHCTL_SOURCE` / `CLASHCTL_HOME` 见 [Clash 文首](clash_proxy.md)，可留在系统盘用户目录 |
| 系统配置 / 驱动 | `/etc/docker`、`/etc/containerd`、驱动和系统工具保留系统默认位置 |
| 容器内路径 | `/workspace/dual_arm_VLA`、`/root/.cache`、`/opt/conda` 是固定容器路径，通常不替换；实际占哪块宿主盘由挂载和 Docker 存储决定 |

在**宿主机**设置并核对，确认数据盘已挂载后再创建目录：

```bash
export DATA_ROOT="/data"              # 替换成自己的实际数据盘挂载点
# 没有独立数据盘时改用：export DATA_ROOT="$HOME"
findmnt -T "$DATA_ROOT"
df -hT / "$DATA_ROOT"
```

如果预期的数据盘未挂载，先完成挂载，不要把系统盘上的同名目录误当数据盘。
确认设备和空间符合预期后，再设置项目父目录；本篇第 3 节才会创建它：

```bash
export WORK="$DATA_ROOT/work"
```

Docker `data-root` / containerd `root` 的配置位置和验证命令见
[统一说明第 3 节](storage_layout.md#3-docker-另外需要设置的地址)，应在本篇第 1 节之后、
**第 2 节首次拉镜像之前**完成；保留已有 NVIDIA runtime / proxy 配置。
新 SSH / tmux 会话重新加载自己的路径设置；已有存储改位置前需要备份与迁移，改变量不会搬文件。

适用：Ubuntu 22.04 / 24.04 x86_64 云服务器，4090 / A100 / L40S 等 Track A GPU。
RTX 5090 需要额外的 torch / CUDA / OIDN 适配，见第 7 节。
**本方案已做静态检查，尚未完成 Docker 镜像构建及容器 GPU 闭环实测。**
采集、训练、评估参数沿用[云服务器 Runbook](cloud_server_runbook.md)。

仓库提供的文件：

| 文件 | 用途 |
| --- | --- |
| `docker/Dockerfile` | CUDA 12.4 基础镜像、系统依赖、uv、Miniconda |
| `docker/compose.yaml` | GPU / Vulkan、宿主网络、代理环境、持久卷 |
| `docker/.env.example` | HTTP 代理地址、HF 入口和编译参数示例 |
| `docker/gpu-check.sh` | 下载大型资产前检查 NVIDIA GPU 和 Vulkan |
| `docker/.dockerignore` | 仅发送镜像所需文件，排除实际 `.env` |

镜像只准备系统工具。Python 环境、资产与 CuRobo 在有 GPU 的运行容器中安装；
现有 setup 脚本会查询实际 GPU 架构，不适合在常规 `docker build` 阶段编译。

## 1. 宿主机准备

先在宿主机完成 [Clash 下载、订阅及网络预检](clash_proxy.md)，保证 `clashctl on`
后 GitHub、PyPI、PyTorch 和 HF 下载地址可用。Clash 留在宿主机运行。

服务器必须能运行 Docker daemon，并通过 NVIDIA Container Toolkit 注入 GPU。
云厂商提供的普通容器实例未必具备这些条件；没有 daemon / GPU runtime 配置权限时，
直接用[非 Docker 云服务器流程](cloud_server_runbook.md)，或选择厂商提供的 GPU Docker 实例。
宿主机需有可用 NVIDIA 驱动；容器不安装内核驱动：

```bash
nvidia-smi
df -h
```

### Docker Engine 与 Compose

若云镜像已有 Docker / Compose，先检查版本并跳过安装。
新 Ubuntu 使用 [Docker 官方 apt 安装步骤](https://docs.docker.com/engine/install/ubuntu/)
配置仓库后，安装：

```bash
sudo apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
docker --version
docker compose version
```

以下宿主机命令假设当前用户能运行 `docker`。权限不足可用 `sudo docker`；
若管理员把用户加入 `docker` 组，重新登录后再启用 Clash。

### NVIDIA Container Toolkit

宿主机已经配置好 GPU 容器 runtime 时跳过本段。Ubuntu 安装方式参考
[NVIDIA 官方指南](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)：

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

代理下 `sudo apt` 无法联网时，按 [Clash 文档](clash_proxy.md)显式传递代理变量。
重启 Docker 会影响正在运行的容器，以上初始化步骤安排在启动实验前。

## 2. 四个网络环节分别配置

| 环节 | 谁发起下载 | 配置 |
| --- | --- | --- |
| 宿主机 clone / curl / apt | 当前终端中的程序 | `clashctl on`；sudo 场景显式传变量 |
| `docker pull` / 构建基础镜像拉取 | Docker daemon / builder | daemon 独立配置代理；外置 BuildKit 也需配置其网络 |
| Dockerfile 中的 `RUN apt/curl` | 构建阶段 | Compose 的 `build.network: host` + 预定义代理 build args |
| 容器内 `git/uv/HF/conda` | 运行容器 | `network_mode: host` + Compose 的代理 environment |

本方案默认 Linux Docker Engine 的本机 builder。构建和运行都使用宿主网络，
所以 `http://127.0.0.1:<mixed端口>` 指向宿主 Clash；无需开启 `allow-lan`、TUN 或
`NET_ADMIN`。bridge 网络里 `127.0.0.1` 指向容器自己，不能直接照搬此地址。

### Docker daemon 的拉镜像代理

终端里的 `clashctl on` 不会修改已运行的 daemon。按
[Docker daemon 代理文档](https://docs.docker.com/engine/daemon/proxy/)配置。
以下适用于由 systemd 管理的 rootful Docker；已经有代理配置时修改现有项，避免重复配置。
在已启用 Clash 的同一终端执行，使用 `clashctl status` 确认端口：

```bash
clashctl status
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/clash-proxy.conf >/dev/null <<EOF
[Service]
Environment="HTTP_PROXY=${http_proxy}"
Environment="HTTPS_PROXY=${https_proxy}"
Environment="NO_PROXY=localhost,127.0.0.1,::1"
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker
docker pull nvidia/cuda:12.4.1-base-ubuntu22.04
```

Clash 必须先运行；端口变动后同步修改此文件并重启 daemon。
无 systemd、rootless 或远端 builder 请按对应官方配置路径处理，不能假定本机 loopback 可达。
终端变量与 `build --network host` 均不能替代此步骤。

如果基础镜像始终无法拉取，可以在能联网的机器构建同一镜像并 `docker save`，上传后
`docker load`；但后续 Python、Git、资产下载仍需可用网络。完整迁移见第 6 节。

## 3. 克隆本仓库与配置 Compose

宿主机执行：

```bash
: "${WORK:?请先按文首设置实际的宿主机 WORK 路径}"
mkdir -p "$WORK"
cd "$WORK"
git clone <YOUR_GITHUB_REPO_URL> dual_arm_VLA
cd dual_arm_VLA
cp docker/.env.example docker/.env
chmod 600 docker/.env
mkdir -p outputs/docker
```

编辑 `docker/.env`，将 `PROXY_URL` 改成 `clashctl status` 的实际 **HTTP(S)** 代理地址。
HTTPS 目标的代理仍用 `http://`；不需要代理时留空。建议先测试 HF 官方站：

```dotenv
PROXY_URL=http://127.0.0.1:7890
NO_PROXY=localhost,127.0.0.1,::1
HF_ENDPOINT=https://huggingface.co
CUDA_TOOLKIT_VERSION=12.4.1
MAX_JOBS=2
```

本文件已被 Git 忽略，不要填订阅 URL；这里只需要本地 mixed 端口。
Compose 会传入大小写两套代理变量，`NO_PROXY` 保证策略服务与仿真通过 localhost 通信。
构建使用 Docker 的预定义代理参数，不把代理写为镜像 `ENV`，参见
[Docker build 代理参数](https://docs.docker.com/build/building/variables/#proxy-arguments)。

后续都在**宿主机仓库根目录**使用这个函数，避免遗漏配置文件：

```bash
dc() { docker compose --env-file docker/.env -f docker/compose.yaml "$@"; }
dc config --quiet
dc build
dc up -d
dc exec robotwin robotwin-gpu-check
```

如果使用 `sudo docker`，函数中也替换成 `sudo docker compose`。新宿主终端需重新定义 `dc`。
修改代理 `.env` 后运行 `dc up -d --force-recreate` 更新容器环境；已有进程不会自动刷新。

预检应显示 NVIDIA GPU 和 NVIDIA Vulkan device，并以 `GPU and NVIDIA Vulkan preflight passed`
结束。只有 `nvidia-smi` 正常还不够；[NVIDIA 官方说明](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/docker-specialized.html#driver-capabilities)
中 `graphics` 用于 OpenGL/Vulkan。本 Compose 已设置
`NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics` 和 GPU reservation，
写法参考 [Compose GPU 文档](https://docs.docker.com/compose/how-tos/gpu-support/)。
预检失败先处理 runtime / 驱动 / ICD，不要继续下载十几 GB 资产。
Toolkit 可以把 ICD 注入 `/etc/vulkan/icd.d/`，文件名也可能带架构后缀，见
[NVIDIA 的注入实现](https://github.com/NVIDIA/nvidia-container-toolkit/blob/main/internal/discover/graphics.go)。
自检已兼容 `/etc` 和 `/usr/share` 两处；容器 GPU 预检以实际枚举出的 NVIDIA Vulkan 设备为准。

容器使用 host 网络，策略服务的监听端口也在宿主机上；云安全组只开放实际需要的入口，
不必放行策略服务或 Clash 管理端口。不要在同一宿主同时启动争用相同端口的评估任务。

## 4. 首次初始化（容器内）

进入容器：

```bash
dc exec robotwin bash
```

以下在**容器内**执行，固定工作路径，不使用宿主机的 `WORK` / 数据盘地址，
也不要复制裸机部署文首的缓存变量块覆盖 Compose 已设置的容器缓存路径：

```bash
cd /workspace/dual_arm_VLA
export WORK=/workspace

# 先验证容器网络继承成功
curl -fIL --connect-timeout 10 --max-time 30 https://github.com
curl -fIL --connect-timeout 10 --max-time 30 https://pypi.org/simple/numpy/
curl -fIL --connect-timeout 10 --max-time 30 https://download.pytorch.org/whl/cu121/
curl -fIL --connect-timeout 10 --max-time 60 \
  "${HF_ENDPOINT}/datasets/TianxingChen/RoboTwin2.0/resolve/main/embodiments.zip"

# 必须先显式固定 RoboTwin 版本；setup 本身只打印 pinned commit，不会强制 checkout
mkdir -p third_party
git clone https://github.com/RoboTwin-Platform/RoboTwin.git third_party/RoboTwin
git -C third_party/RoboTwin checkout ea8b21121ebb3cd201ff5b3fe361944ac94eda3f
git -C third_party/RoboTwin submodule update --init --recursive
git -C third_party/RoboTwin rev-parse HEAD
git -C third_party/RoboTwin/XPolicyLab rev-parse HEAD
# 应为 ea8b211... / fa431ec...

uv python install 3.10
uv sync --project envs/robotwin --frozen

# randomized 评估要纹理；只做 clean smoke 可去掉 WITH_TEXTURES=1
WITH_TEXTURES=1 bash scripts/02_download_assets.sh

# assets 必须先存在；这里会应用补丁、安装 editable 包、装 CUDA 并按实际 GPU 编译 CuRobo
bash scripts/01_setup_robotwin.sh

# setup 自检后，再验证真正离屏渲染
cd third_party/RoboTwin
CUDA_VISIBLE_DEVICES=0 ../../envs/robotwin/.venv/bin/python scripts/test_render.py
# 预期最后一行：Render Well
cd /workspace/dual_arm_VLA
```

镜像中已提供 conda/uv 和系统依赖，不需再次安装。若最新 Miniconda 在非交互模式报
`CondaToSNonInteractiveError`，先阅读其提示和条款，决定是否接受后按报错给出的命令处理，
再重跑 setup；镜像不会自动替你接受条款。

下载失败只重试对应步骤，复用持久缓存。重新进入同一组卷时，跳过已有 clone / 初次
`uv sync`，直接 `make check` 验证。单独运行 `uv sync` 可能移除 setup 后额外安装的
XPolicyLab / CuRobo；确需重新同步时随后重跑 `01_setup_robotwin.sh`。
不要让多个容器同时安装/修改同一组环境卷。

## 5. 采集、训练、评估

仍在容器内，从 `cd /workspace/dual_arm_VLA` 开始。正式参数和各项预期见
[云服务器 Runbook 第 7–11 节](cloud_server_runbook.md#7-正式采集50-条-clean)。

```bash
bash scripts/03_collect_data.sh handover_block demo_clean 50 0
ACT_IMAGE_W=640 ACT_IMAGE_H=480 \
  bash scripts/04_prepare_act.sh handover_block demo_clean
EPOCHS=6000 BATCH_SIZE=16 SAVE_FREQ=1000 \
  bash scripts/05_train_act.sh handover_block 0 0

# 正式云端评估采用官方 temporal_agg；24GB 卡可能需要降低 batch / 渲染开销
sed -i 's/temporal_agg: false/temporal_agg: true/' \
  third_party/RoboTwin/XPolicyLab/policy/ACT/deploy.yml
export ACT_IMAGE_W=640 ACT_IMAGE_H=480 ACT_DEVICE=cuda:0 EXPERT_CHECK=1
RUN=RoboTwin-handover_block-arx_x5-joint-0
bash scripts/06_eval_act.sh handover_block demo_clean 0 "$RUN" 100
bash scripts/06_eval_act.sh handover_block demo_randomized 0 "$RUN" 100
envs/robotwin/.venv/bin/python scripts/07_summarize_eval.py
```

长任务可在容器 `tmux new -s robotwin` 中运行，断开 SSH 后用
`dc exec robotwin tmux attach -t robotwin` 回到会话；停止或重建容器仍会终止任务。
`dc up -d` 只是保持容器运行，不会自动开始采集或训练。

## 6. 持久化、备份与重启

Compose 项目名固定为 `dual-arm-vla`，持久化位置如下；named volumes 在哪块盘上由文首的
Docker 存储设置决定，不跟随宿主机 `WORK` 自动改变：

| 容器位置 | 存储 | 内容 |
| --- | --- | --- |
| `/workspace/dual_arm_VLA` | 宿主仓库 bind mount | 受版本控制的脚本、配置、文档；容器内修改也会反映到宿主 |
| `third_party/` | `robotwin-third-party` named volume | RoboTwin、资产、原始/处理后数据、checkpoint、评估视频 |
| `envs/robotwin/.venv` | `robotwin-venv` named volume | 容器专用 Python 环境 |
| `envs/robotwin/.cuda`、`.cuda_home` | 两个 CUDA named volumes | 编译工具链及相对路径链接 |
| `/root/.cache` | `download-cache` named volume | uv Python、包缓存、HF、conda 缓存 |
| `outputs/` | 宿主 `outputs/docker/` | 日志、`results.csv` 等小体积结果 |

卷的实际名称有 `dual-arm-vla_` 前缀，可用 `docker volume ls` 查看。
容器看不到宿主已有的 `third_party/` 和 venv，而是使用独立卷，避免不同绝对资产路径与
Python 环境混用。`dc down` / `dc up -d` 保留卷，**不要运行 `dc down -v` 或清理这些卷**。
默认容器以 root 运行，宿主 `outputs/docker` 可能出现 root 所有的文件；需要编辑时，
在任务停止后仅调整该输出目录：`sudo chown -R "$(id -u):$(id -g)" outputs/docker`。

在宿主机导出重要实验产物：

```bash
mkdir -p backups/docker
dc cp robotwin:/workspace/dual_arm_VLA/third_party/RoboTwin/XPolicyLab/policy/ACT/checkpoints \
  backups/docker/
dc cp robotwin:/workspace/dual_arm_VLA/third_party/RoboTwin/eval_result backups/docker/
dc cp robotwin:/workspace/dual_arm_VLA/third_party/RoboTwin/data backups/docker/
```

备份很占磁盘，按需要选择数据；停止正在写文件的任务后再拷贝。
这些目录与输出均不应提交 Git。单独搬运镜像：

```bash
docker save dual-arm-vla/robotwin:cu124 -o "$WORK/dual-arm-vla-robotwin.tar"
# 上传到目标机器自己选择的数据盘目录后：docker load -i <实际归档路径>
```

镜像不包含 bind mount 源码和 named volumes，`save/load` 不能迁移数据、venv 或资产。
新机器应拉取同一仓库版本、恢复需要的产物，再按第 4 节重建 GPU 对应的环境；
资产配置在容器内重新生成，不要复制宿主 `.venv` 或携带旧绝对路径直接运行。
暂停服务器前保存输出和 checkpoint，并按云厂商规则确认系统盘 / Docker 卷会被保留。

## 7. RTX 5090 分支

Docker 不能消除 Blackwell 兼容性问题。本方案默认 torch 2.4.1 / CUDA 12.4，
不可直接作为 5090 环境。为 5090 使用独立仓库 checkout，先在第 3 节的 `docker/.env`
中覆盖以下值，保留实际代理与 HF 配置：

```dotenv
BASE_IMAGE=nvidia/cuda:12.8.1-base-ubuntu22.04
ROBOTWIN_IMAGE=dual-arm-vla/robotwin:cu128
CUDA_TOOLKIT_VERSION=12.8.1
```

宿主机的 Compose 函数同时换项目名，隔离 Track A 已编译的环境卷：

```bash
dc() { docker compose --env-file docker/.env -f docker/compose.yaml -p dual-arm-vla-5090 "$@"; }
dc build
dc up -d
dc exec robotwin robotwin-gpu-check
```

之后进入容器，完成第 4 节的 RoboTwin clone / checkout，在第一次 `uv sync` 之前，
先执行[云 Runbook 第 4 节 Track B](cloud_server_runbook.md#track-brtx-5090sm_120)
的 pyproject / lock 修改与同步（该文档的 `$WORK` 在容器内设为 `/workspace`）。
再下载资产、运行 CUDA 12.8 setup，按云 Runbook 第 6 节替换 OIDN 2.3.3。
标签和基础镜像只决定系统 profile，不能代替 Python lock 适配。
5090 的 CuRobo v0.7.8 + torch 2.7 / CUDA 12.8 组合尚未实测；在编译和渲染通过前不能认为部署完成。

## 8. 常见问题

| 现象 | 优先检查 |
| --- | --- |
| `docker: unknown command: docker compose` | 安装 `docker-compose-plugin`，使用 Compose v2 命令 |
| `could not select device driver ... gpu` | 宿主 NVIDIA Container Toolkit / `nvidia-ctk runtime configure` |
| 容器里 `nvidia-smi` 正常但 Vulkan 没 NVIDIA | `graphics` capability、宿主驱动、ICD；先过 `robotwin-gpu-check` |
| `docker pull` 卡住，宿主 curl 正常 | 第 2 节 daemon 代理；确认 Clash 仍运行及端口未变 |
| build 的 `apt/curl` 失败 | `.env` PROXY_URL、build host 网络、builder 是否远端/外置 |
| 运行容器下载失败 | 代理端口、容器环境、HF_ENDPOINT；修改 `.env` 后 recreate |
| 环境忽然缺 XPolicyLab / CuRobo | 是否单独跑了 `uv sync`；重跑 setup 恢复 editable 安装 |
| setup 报资产缺失 | 必须先下载/解压 objects 与 embodiments |
| 看不到宿主已下载的资产 | `third_party` 使用独立卷；按第 4 节下载，或导入后重新生成资产路径配置 |
| 找不到结果或重建后丢失 | 日志在宿主 `outputs/docker`；数据/checkpoint 在 named volume；核查项目名是否改变 |
| 存储不足 | 本身资产/数据约 56GB，另有镜像、CUDA、缓存与归档；建议至少 150GB 可用 |
| `cannot create buffer` / OOM | 按云 Runbook 降 batch / 渲染开销，显存需同时容纳 SAPIEN 与 policy |
