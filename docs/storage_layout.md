# 执行前：设置安装路径与系统盘 / 数据盘

**本文中的 `/data` 只是示例，必须替换成你自己的实际数据盘挂载点。**
没有独立数据盘时，用 `$HOME` 等已有可写目录，并确认所在磁盘容量足够。
`/workspace`、`/root`、`$HOME` 等目录名本身不能证明它们属于数据盘。

## 1. 先确认磁盘，再创建项目目录

在准备安装的机器上执行：

```bash
export DATA_ROOT="/data"              # 改成自己的实际数据盘挂载点
# 没有独立数据盘时，改用这一行：export DATA_ROOT="$HOME"
findmnt -T "$DATA_ROOT"
df -hT / "$DATA_ROOT"
```

核对 `findmnt` 的 SOURCE / TARGET 与云平台标明的磁盘一致。若预期有数据盘却显示目录不存在，
或实际落在系统根分区 `/`，先按云平台方式挂载，再继续；不要直接新建一个同名 `/data`
目录就当作数据盘使用。同时确认该盘是持久盘还是实例释放即删除的临时盘。

## 2. 裸机部署需要设置的地址

系统依赖、驱动和 `/etc` 配置按系统默认位置安装；将体积大的项目、环境、缓存放在选定的数据目录。

| 需要设置的位置 | 默认 / 示例 | 在哪里修改 |
| --- | --- | --- |
| 项目父目录 `WORK` | `$DATA_ROOT/work` | 克隆仓库前；项目位于 `$WORK/dual_arm_VLA` |
| Miniconda 安装目录 `MINICONDA_DIR` | `$DATA_ROOT/tools/miniconda3` | 安装命令 `-p` 和后续 `source` 必须一致 |
| uv 包缓存 `UV_CACHE_DIR` | `$DATA_ROOT/cache/uv` | 第一次 `uv python install` / `uv sync` 前导出 |
| uv 管理的 Python `UV_PYTHON_INSTALL_DIR` | `$DATA_ROOT/cache/uv/python` | 第一次下载 Python 前导出；venv 会依赖这里，不要当普通缓存清理 |
| HF 缓存 `HF_HOME` | `$DATA_ROOT/cache/huggingface` | 下载资产 / 模型前导出 |
| PyTorch 权重缓存 `TORCH_HOME` | `$DATA_ROOT/cache/torch` | 第一次下载 ACT 使用的预训练视觉权重前导出 |
| conda 包缓存 `CONDA_PKGS_DIRS` | `$DATA_ROOT/cache/conda/pkgs` | 安装 CUDA toolkit 前导出 |
| 临时目录 `TMPDIR` | `$DATA_ROOT/tmp` | 大文件解压 / 编译前导出；显式写死的 `/tmp` 需另行替换 |
| Clash 源码 / 安装目录 | `CLASHCTL_SOURCE` / `CLASHCTL_HOME` | 见 [Clash 文档开头](clash_proxy.md)；体积小，可留在系统盘用户目录 |
| uv 可执行文件 | `$HOME/.local/bin` | 与 uv 缓存、Python、项目 venv 分开；本文保留默认位置 |

完成第 1 节后，在同一个 Shell 设置：

```bash
export WORK="$DATA_ROOT/work"
export CACHE_ROOT="$DATA_ROOT/cache"
export MINICONDA_DIR="$DATA_ROOT/tools/miniconda3"
export UV_CACHE_DIR="$CACHE_ROOT/uv"
export UV_PYTHON_INSTALL_DIR="$CACHE_ROOT/uv/python"
export HF_HOME="$CACHE_ROOT/huggingface"
export TORCH_HOME="$CACHE_ROOT/torch"
export CONDA_PKGS_DIRS="$CACHE_ROOT/conda/pkgs"
export TMPDIR="$DATA_ROOT/tmp"
mkdir -p "$WORK" "$CACHE_ROOT" "$(dirname "$MINICONDA_DIR")" \
  "$UV_CACHE_DIR" "$UV_PYTHON_INSTALL_DIR" "$HF_HOME" "$TORCH_HOME" "$CONDA_PKGS_DIRS" "$TMPDIR"
```

将确认后的变量保存到自己的 Shell 配置或路径配置脚本，新 SSH / tmux 会话重新加载。
在多台机器上分别填写，避免加载另一台机器的挂载路径。

当前脚本从仓库自身位置推导路径：`envs/robotwin/.venv`、`.cuda`、`.cuda_home`、
`third_party/RoboTwin`、资产、原始数据、预处理、checkpoint、视频和 `outputs`
均跟随仓库根目录；把仓库最初就 clone 到数据盘即可，不需要逐项改脚本。
HF 的 `local_dir` 资产下载仍会落到 `third_party/RoboTwin/assets`，仅设置 `HF_HOME` 不会搬走这些资产。

已经安装的仓库、venv、conda 和资产配置可能包含绝对路径。更换安装地址后应重新创建环境、
重新生成资产路径配置；修改 `WORK` 变量不会迁移旧文件。

## 3. Docker 另外需要设置的地址

**把仓库放到数据盘，不会自动把 named volumes、镜像或容器层也放过去。**
以下配置在第一次 pull / build / up 前确认；不要在正在运行实验时直接更换存储根目录。

| 数据 | 实际位置由谁决定 | 需要设置 / 检查 |
| --- | --- | --- |
| 宿主源码、日志、备份 | `WORK` 下的仓库目录 | Compose bind mount 使用仓库目录；`outputs/docker`、`backups/docker` 跟随它 |
| `third_party`、venv、CUDA、下载缓存 named volumes | Docker daemon 的数据目录 | `docker info --format '{{.DockerRootDir}}'`；必要时设置 `data-root` |
| 镜像、容器可写层、构建缓存 | 当前 Docker 存储后端 / builder | 经典存储后端随 Docker 根目录；containerd image store 还需单独检查 containerd `root`；外置 builder 检查其自己的存储 |
| 容器 `/workspace/dual_arm_VLA` | Compose 的容器目标路径 | 固定接口，通常不改；它不代表宿主机有名为 `/workspace` 的数据盘 |
| 容器 `/root/.cache`、`/opt/conda` | 前者映射缓存卷，后者在镜像内 | 不替换为宿主挂载点；通过卷、镜像所在磁盘决定实际占用 |
| `/etc/docker`、`/etc/containerd` | 系统盘配置 | 配置文件留在系统盘，数据目录可以指向数据盘 |

Docker Engine 的 Linux 数据目录通常是 `/var/lib/docker`；采用 containerd image store 时，
镜像和容器快照另由 containerd 管理，`data-root` 不会改变该部分路径。
新安装的 Engine 29+ 默认使用这种存储后端，升级安装可能不同，按实际配置确认。
参见 [Docker 数据目录说明](https://docs.docker.com/engine/daemon/#daemon-data-directory)
和 [containerd 存储说明](https://docs.docker.com/engine/storage/containerd/#disk-space-usage)。

对于自己管理的 rootful Linux Docker，新机器可在 `/etc/docker/daemon.json` 中加入以下字段。
**`/data/docker` 改成实际绝对路径，并与已有 runtimes / proxies 等字段合并，不能覆盖整个配置：**

```json
{
  "data-root": "/data/docker"
}
```

如果使用 containerd image store，还需在该 daemon 使用的 `/etc/containerd/config.toml`
顶层设置 `root`；保留原有版本和插件配置，示例字段：

```toml
root = "/data/containerd"
```

JSON / TOML 中填写真实绝对路径，不能写 `$DATA_ROOT` 期待自动展开。
新配置生效需要在空闲时重启相关服务；已有镜像、卷和容器不会因改配置自动搬迁，
已有安装要先备份并完成存储迁移，不能直接换成空目录后继续实验。
rootless、厂商托管 Docker 或外置 builder 使用其各自配置入口。

```bash
docker info --format '{{.DockerRootDir}}'
docker info --format '{{.DriverStatus}}'
# 用上一条输出的实际 Docker 根目录替换这里的示例，再检查它属于哪块盘
findmnt -T /data/docker
df -hT /data/docker
# Compose 首次创建卷后，可进一步核查实际卷位置
docker volume inspect dual-arm-vla_robotwin-third-party --format '{{.Mountpoint}}'
```

容器中的安装步骤继续使用 `/workspace/dual_arm_VLA` 和镜像内路径，不要重新运行第 2 节的
宿主机路径初始化来覆盖容器已有的缓存变量。完整执行命令见 [Docker 部署](docker_deployment.md)。
