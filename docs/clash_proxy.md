# 无图形界面 Linux 的 Clash 代理

## 执行前：设置源码、安装与临时文件地址

先按[安装路径与磁盘说明](storage_layout.md)确认本机系统盘 / 数据盘。
**本篇的 `/home/ljk/...` 是作者机器的参考地址，不是读者必须使用的目录。**
Clash 体积较小，下列默认值可保留在系统盘用户目录；需要放数据盘时，在安装前改成自己实际的绝对路径。
`/data` 等示例只有确认已挂载后才代表数据盘；没有盘位区分时使用 `$HOME` 即可。

| 需要设置的位置 | 默认值 | 哪些命令必须一致 |
| --- | --- | --- |
| `CLASHCTL_SOURCE` 源码目录 | `$HOME/tools/no_gui_linux_clash/clashctl` | clone / 解压目标和 `install.sh` 位置 |
| `CLASHCTL_HOME` 安装与订阅目录 | `$HOME/.clashctl` | 安装 `--home`、后续 `source`、服务管理都用同一个地址 |
| `CLASHCTL_TMP_DIR` 下载临时目录 | `${TMPDIR:-/tmp}` | 源码归档下载与解压读取地址；可改为数据盘的临时目录 |
| 本地订阅 YAML 路径 | 第 2 节用 `$HOME/clash-config.yaml` 举例 | 改成自己上传文件的真实路径，不受源码目录控制 |

在当前终端设置一次，后续命令沿用；新 SSH / tmux 会话重新加载自己的设置：

```bash
export CLASHCTL_SOURCE="${CLASHCTL_SOURCE:-$HOME/tools/no_gui_linux_clash/clashctl}"
export CLASHCTL_HOME="${CLASHCTL_HOME:-$HOME/.clashctl}"
export CLASHCTL_TMP_DIR="${CLASHCTL_TMP_DIR:-${TMPDIR:-/tmp}}"
mkdir -p "$CLASHCTL_TMP_DIR"
```

修改上面的默认地址或预先导出自定义值；源码目录与安装目录必须分开。
已经安装后更换变量不会搬迁服务与订阅，迁移前先备份并按新的安装地址重新设置。

云服务器先把网络打通，再安装 Python、下载资产或构建 Docker。按本页验证 GitHub、PyPI、
PyTorch 和 Hugging Face 的实际下载链路；连通性未通过时先处理代理，不要反复重跑完整安装。

本机 `/home/ljk/tools/no_gui_linux_clash/` 下的项目实际是
[nelvko/clashctl](https://github.com/nelvko/clashctl)，源码位于其 `clashctl/` 子目录。
它负责安装和管理 Mihomo / Clash 内核，不提供代理节点；需要自行准备可用的订阅。
以下命令按本机源码版本 `4ec42a9f33108a16281bdad4eace7ccce94ae3b2` 核对，使用 Bash。

## 1. 下载与安装

如果机器还没有 `git`、`curl`、`tar`：

```bash
sudo apt update
sudo apt install -y ca-certificates curl git tar
```

### 能直连 GitHub

在新机器上使用文首选定的源码和安装目录：

```bash
: "${CLASHCTL_SOURCE:?请先按文首设置源码目录}"
: "${CLASHCTL_HOME:?请先按文首设置安装目录}"
export CLASHCTL_REF=4ec42a9f33108a16281bdad4eace7ccce94ae3b2
mkdir -p "$(dirname "$CLASHCTL_SOURCE")"
git clone https://github.com/nelvko/clashctl.git "$CLASHCTL_SOURCE"
git -C "$CLASHCTL_SOURCE" checkout "$CLASHCTL_REF"
bash "$CLASHCTL_SOURCE/install.sh" --local --home "$CLASHCTL_HOME" --gh-proxy=
```

本机已存在源码时，跳过 clone 和 checkout，直接执行最后一条安装命令。
`--local` 使用这份源码，但仍会按需下载内核、yq 等组件，不代表离线安装。

### GitHub 本身连不上：先用下载加速入口引导

先在新机器的空源码目录下载固定版本归档。`GH_PROXY` 是上游 README 给出的公共 GitHub
下载代理前缀，可用性取决于当时网络；只用它取得公开源码/组件，不向它发送订阅地址。

```bash
export GH_PROXY=https://gh-proxy.org
export CLASHCTL_REF=4ec42a9f33108a16281bdad4eace7ccce94ae3b2
: "${CLASHCTL_SOURCE:?请先按文首设置源码目录}"
: "${CLASHCTL_HOME:?请先按文首设置安装目录}"
: "${CLASHCTL_TMP_DIR:?请先按文首设置临时目录}"
mkdir -p "$CLASHCTL_SOURCE"
curl -fL --connect-timeout 10 --max-time 180 --retry 2 \
  "${GH_PROXY%/}/https://github.com/nelvko/clashctl/archive/${CLASHCTL_REF}.tar.gz" \
  -o "$CLASHCTL_TMP_DIR/clashctl-source.tar.gz"
tar -xzf "$CLASHCTL_TMP_DIR/clashctl-source.tar.gz" --strip-components=1 -C "$CLASHCTL_SOURCE"
CLASHCTL_DOWNLOAD_TIMEOUT=180 bash "$CLASHCTL_SOURCE/install.sh" \
  --local --home "$CLASHCTL_HOME" --gh-proxy "$GH_PROXY"
```

不要在已有源码目录上解压覆盖。入口不可用时，更换可信下载入口，或在能联网的机器下载
这个源码归档后用 `scp` 上传，再解压、安装。仅上传源码仍需要安装依赖的下载通道；
不要把包含订阅和运行配置的整个 `~/.clashctl` 当作公开源码分享。

安装默认自动选择服务管理方式。有些云平台提供的是容器，没有可用的 systemd，或普通用户
没有 systemd user session；这时在上述安装命令末尾加 `--service nohup`。这类模式依赖
所在实例存活，实例重启后执行 `clashctl start`，不能假定有系统服务自动启动。

安装器如果询问订阅链接，可回车跳过，统一在下一节导入。已经在安装过程中导入过同一订阅时，
下一节跳过 `sub add`，直接运行 `clashctl on` 和 `clashctl status`，避免重复添加。

## 2. 加载命令、导入订阅、启用代理

在**当前终端**加载安装后的 Shell 集成：

```bash
export CLASHCTL_HOME="${CLASHCTL_HOME:-$HOME/.clashctl}"
source "$CLASHCTL_HOME/scripts/cmd/clashctl.sh"

# 交互输入订阅链接，避免直接写入 shell history
clashctl sub add --name cloud --use
clashctl on
clashctl status
```

也支持 `clashctl sub add --name cloud --use '<订阅链接>'`；订阅通常带 token，
不要写进本仓库、Dockerfile、Compose、日志或截图。

已有原生 Clash/Mihomo YAML 时，也可上传后本地导入：

```bash
clashctl sub add --name cloud-file --use --raw "file://$HOME/clash-config.yaml"
```

文件需包含有效的 `proxies` 或 `proxy-providers`；后者仍可能依赖后续网络下载。
安装时跳过订阅会生成直连配置，内核显示 running 并不代表有代理节点。

`clashctl on` 会自动启动内核，并给当前 Shell 设置大小写两套 `http_proxy`、
`https_proxy`、`all_proxy` 和 `no_proxy`，其后启动的 `git`、`curl`、`uv`、Python
才会继承。它不是全系统开关；在 `bash -c` 子进程里执行不能改变父终端。
新 SSH 会话或新 tmux 窗口里重新加载并执行 `clashctl on`；已有训练/下载进程不会被追溯修改。

默认 mixed 端口是 `7890`，遇到冲突可能自动改用其他端口，始终以 `clashctl status`
显示的 HTTP(S) 地址为准。HTTPS 目标同样通过 `http://127.0.0.1:<端口>` 代理 CONNECT，
不要擅自把代理地址改成 `https://`。

### 云服务器监听配置

```bash
clashctl mixin -e
```

在编辑器中保留其他配置，并确保以下字段存在：

```yaml
mixed-port: 7890
allow-lan: false
external-controller: "127.0.0.1:9090"
```

保存退出后工具会合并配置并重启。重新运行 `clashctl on` 和 `clashctl status`，让当前 Shell
跟随最新端口。不要直接修改 `data/runtime.yaml`，它会被重新生成。默认模板的 controller
监听 `0.0.0.0:9090`，云机建议按上例收紧；不必开放安全组的 7890/9090，也不必开启 TUN。

如需本地浏览器管理面板，在自己电脑上建立 SSH 隧道（端口按实际配置修改）：

```bash
ssh -N -L 9090:127.0.0.1:9090 <USER>@<SERVER_IP>
```

服务器上用 `clashctl ui` 查看面板入口，`clashctl secret` 查看/管理密钥
（具体选项见 `clashctl secret --help`）；在本地面板中连接 `127.0.0.1:9090`。

## 3. 下载前的连通性门槛

```bash
clashctl status

# -f：HTTP 错误返回失败；-L：跟随跳转；限制等待时间
curl -fIL --connect-timeout 10 --max-time 30 https://github.com
curl -fIL --connect-timeout 10 --max-time 30 https://pypi.org/simple/numpy/
curl -fIL --connect-timeout 10 --max-time 30 https://download.pytorch.org/whl/cu121/

# 测试真正使用的资产下载地址，而不只是 HF 首页
curl -fIL --connect-timeout 10 --max-time 60 \
  https://huggingface.co/datasets/TianxingChen/RoboTwin2.0/resolve/main/embodiments.zip
git ls-remote https://github.com/RoboTwin-Platform/RoboTwin.git HEAD
```

`HTTP/1.1 200 Connection established` 只表示代理隧道建立；仍要检查后续目标站状态及
命令退出码。若经代理失败，先用 `clashctl node` 换节点、`clashctl node delay` 测延迟，
再重试出问题的那一个地址。IPv6 或 fake-IP 解析异常时用 `curl -4` 做对照测试。

通过后再执行[云服务器 Runbook](cloud_server_runbook.md)的环境安装、Git 子模块和资产下载。
本仓库资产脚本默认 `HF_ENDPOINT=https://hf-mirror.com`，可明确选择一种入口：

```bash
# Clash 已开，优先测试并使用 HF 官方站
export HF_ENDPOINT=https://huggingface.co
bash scripts/02_download_assets.sh

# 如果所选节点访问镜像更好，可改用镜像；不要同时反复换代理和入口
# export HF_ENDPOINT=https://hf-mirror.com
```

如果选镜像，也先对同一 `embodiments.zip` 路径做上述 `curl -fIL` 测试。
HF 大文件会跳转到其他存储域名，首页能打开并不保证下载通畅。
`uv sync` / `uv pip` 会继承当前环境变量，无需再写全局 Git 代理。
`sudo` 默认可能清除代理变量；仅在需要时显式传给包管理器：

```bash
sudo env http_proxy="$http_proxy" https_proxy="$https_proxy" \
  no_proxy="$no_proxy" apt-get update
```

## 4. 常用维护与排查

| 目的 / 现象 | 命令或处理 |
| --- | --- |
| 查看内核、当前终端及实际端口 | `clashctl status` |
| 仅启动内核 | `clashctl start`，不会给当前终端设置代理 |
| 当前终端打开 / 关闭代理 | `clashctl on` / `clashctl off` |
| 关闭当前终端代理并停止内核 | `clashctl off --stop`；确认没有共享代理的下载或容器任务 |
| 查看 / 切换 / 更新订阅 | `clashctl sub list` / `clashctl sub use cloud` / `clashctl sub update cloud` |
| 切换节点 / 测速 | `clashctl node` / `clashctl node delay` |
| 查看日志 / 持续追踪 | `clashctl log -n 100` / `clashctl log -f`（参数透传给服务后端 tail / journalctl） |
| `clashctl: command not found` | 重复第 2 节的 `export CLASHCTL_HOME=...` 与 `source` 两条命令，加载安装目录下的 Shell 集成 |
| `Connection refused` | 先 `clashctl start`，再 `clashctl status` / `clashctl log`；检查端口是否变化 |
| `curl` 可用但 `git` 失败 | 检查 `git config --show-origin --get-regexp '.*proxy'`，清理确认已过期的局部/全局配置；SSH 格式 remote 不会自动走 HTTP 代理，部署示例使用 HTTPS URL |
| 宿主机可用、`docker pull` 超时 | Docker daemon 需要独立代理配置，见 [Docker 部署](docker_deployment.md) |
| `sudo` / 新 SSH / tmux 中失效 | 环境变量没有继承；在对应会话启用代理，或仅为需要的命令显式传入 |

成功完成代理检查后，不要在同一部署过程中随意运行 `clashctl update` / `upgrade`；
它们分别更新管理工具和内核，可能改变行为。新版本用法以
[上游 README](https://github.com/nelvko/clashctl)和 `clashctl --help` 为准。
