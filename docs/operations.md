# 运维与排障说明

这份文档面向需要查看日志、停止服务、清理环境或排查问题的使用者。普通日常使用请优先阅读根目录的 `README.md`。

## 推荐排查顺序

遇到问题时，建议按下面顺序检查：

```bash
mise run harness-check
mise run harness-versions
mise run harness-logs
```

如果你是在本仓库里开发这个工具本身，可以使用本地任务：

```bash
./scripts/check-host
./scripts/toolchain versions .
./scripts/compose logs -f
```

## 环境检查

全局使用：

```bash
mise run harness-check
```

本仓库开发：

```bash
./scripts/check-host
```

检查内容包括：

- Homebrew 是否存在（基础依赖，缺失会阻断流程）
- mise 是否可用
- Docker CLI 是否可用
- Docker daemon 是否正在运行
- Docker Compose 是否可用
- 宿主机硬件资源画像（CPU、内存、架构）
- 网络环境归属检测（国内/海外）与下载源延迟排名测速

宿主机画像结果与最优镜像推荐会持久化在 `~/.config/ai-harness/host-profile.toml`，供后续构建自动消费。

Homebrew 是本工具链最基础的包管理工具，缺失时 `check-host` 会提示安装并阻断后续流程。可使用脚本通过清华源安装：

```bash
scripts/install-brew
```

`check-host` 使用 Bash/awk 读写宿主机画像 TOML，不依赖 Python 3.11+ 或 `tomli`。`python3` 仅作为后续扩展的可选工具存在，缺失时不会阻塞宿主机画像生成。

## API Key 检查

全局 `harness-*` 命令会把当前终端里已有的常见 AI 服务环境变量带入容器，例如：

```bash
export OPENAI_API_KEY="你的 Key"
mise run harness-up
```

如果你是在本仓库目录调试，可以复制 `.env.example`，再在当前 shell 中加载需要的变量：

```bash
cp .env.example .env
set -a
source .env
set +a
```

然后运行本地脚本或全局 `harness-*` 命令。

## 构建环境

第一次使用前建议运行：

```bash
mise run harness-build
```

本仓库开发时使用：

```bash
docker build -t ai-dev:latest -f docker/Dockerfile .
```

默认镜像名称是：

```text
ai-dev:latest
```

## 启动、进入、退出

启动完整环境并进入 shell：

```bash
mise run harness-up
```

快速进入工具链 shell：

```bash
mise run harness-shell
```

退出当前 shell：

```bash
exit
```

`harness-up` 会执行完整启动流程：检查本机环境、启动 Redis 和 Qdrant、确认镜像存在，并进入工具链容器。

`harness-shell` 更适合镜像和基础设施已经准备好之后快速进入。

## 停止与清理

停止后台服务并保留数据：

```bash
mise run harness-down
```

彻底清理环境和数据：

```bash
mise run harness-clean
```

区别如下：

| 命令 | 删除容器 | 删除 Qdrant 数据 | 删除镜像 | 日常推荐 |
|---|---:|---:|---:|---:|
| `harness-down` | 是 | 否 | 否 | 是 |
| `harness-clean` | 是 | 是 | 是 | 否 |

如果你不确定该用哪个，优先使用：

```bash
mise run harness-down
```

## 查看日志

查看 Redis 和 Qdrant 日志：

```bash
mise run harness-logs
```

查看项目里的 Agent 日志：

```bash
mise run harness-agent-logs
```

Agent 日志默认读取当前项目目录下的：

```text
logs/agent.log
```

如果文件不存在，命令会提示没有找到日志文件。

## 验证工具版本

```bash
mise run harness-versions
```

预期能看到类似输出：

```text
mise: 2026.x.x
python: Python 3.12.13
node: v22.22.3
pnpm: 11.2.2
uv: uv 0.11.16
git: git version ...
gh: gh version ...
```

具体版本以当前配置为准。

## 冒烟测试

在本仓库目录可以运行：

```bash
python3 smoke_test.py
```

它用于验证：

- 容器内工具版本
- 本机目录和 `/workspace` 是否同步
- `up` / `down` / `clean` 的清理行为
- Qdrant 数据卷保留策略
- 热启动耗时

这更适合维护者或排障场景，普通使用者不需要每天运行。

## 常见故障

### Docker daemon 不可访问

错误通常类似：

```text
Docker CLI is installed, but Docker daemon is not reachable.
```

如果使用 Docker Desktop：

```bash
open -a Docker
docker version
```

如果使用 Colima：

```bash
colima start --runtime docker --cpu 4 --memory 8
docker version
```

### Docker Compose 不可用

先检查：

```bash
docker compose version
docker-compose version
```

Docker Desktop 通常自带 `docker compose`。如果使用 Colima 和独立 Docker CLI，可能需要额外安装：

```bash
brew install docker-compose
```

### 全局任务未生效

如果提示找不到 `harness-up`，重新运行安装脚本：

```bash
~/.ai-harness/scripts/install-global
```

再确认 mise 配置存在：

```bash
ls ~/.config/mise/config.toml
```

如果当前 shell 没有加载 mise，请重新打开终端，或按 mise 的安装提示激活 shell。

### 镜像不存在

构建镜像：

```bash
mise run harness-build
```

如果使用本仓库本地任务：

```bash
docker build -t ai-dev:latest -f docker/Dockerfile .
```

### Colima 下项目目录为空

Colima 默认更适合访问 `$HOME` 下的目录。建议把项目放在：

```text
~/projects
```

如果项目放在 `/tmp` 或其他特殊路径，容器内可能看不到文件。可以移动项目目录，或自行调整 Colima 挂载设置。

### `clean` 后数据不见了

这是预期行为。`harness-clean` 会删除 Qdrant 数据卷。

如果你希望停止服务但保留数据，请使用：

```bash
mise run harness-down
```

## 本地任务与全局任务

全局任务用于普通项目：

```bash
mise run harness-up
mise run harness-down
```

本地脚本用于维护这个仓库：

```bash
./scripts/task-harness-up
./scripts/task-harness-down
```

如果你只是使用这个工具开发自己的 AI 项目，优先使用 `harness-*` 命令。
