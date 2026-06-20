# 架构与实现说明

这份文档面向维护者和需要理解底层实现的技术读者。普通使用请优先阅读根目录的 `README.md`。

## 总体结构

这个项目由三层组成：

| 层级 | 作用 |
|---|---|
| mise 全局任务 | 给用户提供统一命令入口 |
| Docker 工具链镜像 | 封装 Python、Node.js、pnpm、uv、opencode、vim、git、gh 和 mise |
| Docker Compose 基础设施 | 启动 Redis 和 Qdrant |

默认工具链镜像名称：

```text
ai-dev:latest
```

默认基础设施服务：

- Redis: `agent-redis:6379`
- Qdrant: `agent-qdrant:6333`

## 主要文件

```text
.
├── docker-compose.yml
├── docker
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── mise-china.toml
│   └── mise-global.toml
├── scripts
│   ├── check-host
│   ├── compose
│   ├── install-global
│   ├── task-harness-clean
│   ├── task-harness-down
│   ├── task-harness-up
│   ├── toolchain
│   └── lib
│       └── common.sh
├── smoke_test.py
├── pyproject.toml
└── package.json
```

## 本地脚本

仓库根目录不再保存本地 `.mise.toml`。维护 Harness 项目本身时，直接使用脚本入口：

```bash
./scripts/check-host
docker build -t ai-dev:latest -f docker/Dockerfile .
./scripts/task-harness-up
./scripts/task-harness-down
./scripts/task-harness-clean
./scripts/compose logs -f
./scripts/toolchain versions .
```

工具版本的仓库内真源是 `docker/mise-global.toml`。

## 全局任务

`scripts/install-global` 会把 Harness 注册为 mise 全局任务。安装后可以在任意目录运行：

```bash
mise run harness-check
mise run harness-build
mise run harness-up
mise run harness-down
mise run harness-clean
mise run harness-logs
mise run harness-agent-logs
mise run harness-shell
mise run harness-run
mise run harness-versions
```

全局配置会写入：

```text
~/.config/mise/config.toml
```

安装脚本使用标记块更新配置，因此可以重复执行。

## `scripts/toolchain`

`scripts/toolchain` 是 `docker run` 的封装入口。

用法：

```bash
scripts/toolchain shell [project_dir]
scripts/toolchain run <project_dir> <command...>
scripts/toolchain versions [project_dir]
```

示例：

```bash
scripts/toolchain shell .
scripts/toolchain shell ~/projects/my-ai-app
scripts/toolchain run . python --version
scripts/toolchain versions .
```

它负责：

- 确认镜像存在，不存在时自动构建
- 把项目目录挂载到容器内 `/workspace`
- 设置容器工作目录为 `/workspace`
- 传入宿主机 UID、GID 和用户名
- 挂载 Git、GitHub CLI、SSH、GPG 配置
- 挂载 pnpm 和 uv 缓存
- 透传常见 AI 服务环境变量
- 如果 `agent-network` 存在，则加入该网络
- 默认把宿主机 `127.0.0.1:8000-8099` 映射到容器 `8000-8099`

## `/workspace` 的底层实现

镜像设置默认工作目录：

```dockerfile
WORKDIR /workspace
```

容器启动时，`entrypoint.sh` 会确保该目录存在。

真正的项目代码来自 Docker volume 挂载。例如：

```bash
scripts/toolchain shell ~/projects/my-ai-agent
```

等价于把本机目录：

```text
~/projects/my-ai-agent
```

挂载到容器内：

```text
/workspace
```

因此，容器内 `/workspace` 的文件变化会反映到本机项目目录。

## UID/GID 权限设计

`scripts/toolchain` 会传入：

```bash
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
HOST_USER="$(id -un)"
```

`docker/entrypoint.sh` 使用这些值在容器内创建或匹配对应用户，避免容器在宿主机项目目录里生成 root 拥有的文件。

这个设计的目标是：用户在容器里创建的文件，回到 Mac 本机后仍然可以正常编辑和删除。

## 环境变量透传

环境变量从宿主机到容器内用户进程需要经过完整链路。以 `DEEPSEEK_API_KEY` 为例：

### 1. 项目 `.env` 自动加载（`scripts/toolchain`）

在 `shell`/`run`/`versions` 三个派发分支中，解析完 `project_dir` 后即调用 `load_project_env()`。该函数检测 `<project_dir>/.env` 文件是否存在，存在则通过 `set -a; source; set +a` 将文件中的 `KEY=VALUE` 行导出为当前 shell 的环境变量。

### 2. 白名单过滤（`add_env_args()`）

`add_env_args()` 遍历当前 shell 的所有环境变量，按白名单模式过滤：

```text
OPENAI_*
ANTHROPIC_*
GOOGLE_*
LANGCHAIN_*
AZURE_*
MISTRAL_*
GROQ_*
COHERE_*
HF_*
*_API_KEY
```

匹配到的键通过 `docker run -e KEY` 传入容器（取值从宿主机 shell 环境继承）。

同时传入基础设施变量：

```text
REDIS_URL
QDRANT_HOST
QDRANT_PORT
```

### 3. sudo 屏障穿越（`docker/entrypoint.sh`）

容器内入口点以 root 启动。此时 docker 传入的环境变量对 root 可见，但之后 `exec sudo --user #UID` 会重置环境。入口点在 sudo 前收集所有匹配白名单的 API key 并显式追加到 `env` 变量列表中：

```
_api_env+=("KEY=VALUE")
```

再通过 `env ... "${_api_env[@]}" ... cmd` 将这些变量注入到最终用户进程的环境中。

### 完整链路

```
项目 .env 文件
  │  set -a; source (load_project_env)
  ▼
toolchain shell 环境变量
  │  compgen -v → 白名单匹配 (add_env_args)
  ▼
docker run -e DEEPSEEK_API_KEY
  │  Docker 注入到容器 root 环境
  ▼
entrypoint.sh (root) 收集 *_API_KEY
  │  _api_env 数组 → env VAR=VAL (sudo 屏障)
  ▼
容器用户进程（opencode / python / node）
```

## 认证和缓存挂载

启动容器时会尽量复用宿主机配置：

- `~/.gitconfig`
- `~/.config/gh`
- `SSH_AUTH_SOCK`
- `~/.gnupg`
- `~/.local/share/pnpm`
- `~/.cache/uv`

这样做的目标是让容器内也能使用 Git、GitHub CLI、SSH 认证和本地依赖缓存。

## Dockerfile 工作方式

`docker/Dockerfile` 基于 Ubuntu 24.04 构建，主要步骤包括：

- 安装基础系统依赖
- 通过 apt 安装 vim
- 安装 git、curl、build tools 等工具
- 从 GitHub Release 安装 `gh`
- 安装 mise
- 复制 `docker/mise-global.toml` 到镜像内工具链配置位置
- 复制 `docker/mise-china.toml` 作为国内网络模式下的 mise 下载源配置
- 执行 `mise install`（python, node, pnpm, uv, opencode）
- 预创建 opencode 数据目录 `/opt/mise/opencode` 并设置权限
- 设置 `/workspace` 为工作目录
- 使用 `docker/entrypoint.sh` 作为入口

镜像内置 `/opt/mise-config/config.toml` 作为全局工具版本配置，内容来自 `docker/mise-global.toml`。这样即使挂载的业务项目没有自己的 `.mise.toml`，也可以直接使用 Python、Node.js、pnpm、uv 和 opencode。

## Docker Compose 基础设施

`docker-compose.yml` 定义：

- Redis
- Qdrant
- `agent-network`
- `qdrant_data` 数据卷

Qdrant 数据保存在命名卷中：

```text
qdrant_data
```

标准停止流程会保留该数据卷，深度清理流程会删除它。

## `scripts/compose`

`scripts/compose` 是 Docker Compose 的包装器。

它会自动选择可用命令：

- `docker compose`
- `docker-compose`

全局模式下，它会使用：

```bash
-f ~/.ai-harness/docker-compose.yml --project-name ai-harness
```

这样用户即使在任意业务项目目录运行 `harness-up`，也能使用同一套 Harness 基础设施配置。

## 启动流程

`scripts/task-harness-up` 的主要流程：

1. 运行宿主机检查
2. 启动 Redis 和 Qdrant
3. 检查工具链镜像是否存在
4. 如果镜像不存在，则自动构建
5. 进入工具链容器 shell

本地模式使用当前仓库的 compose 配置。全局模式使用 `AI_HARNESS_HOME` 指向的 Harness 安装目录。

## 停止和清理流程

`scripts/task-harness-down`：

- 停止 Redis 和 Qdrant
- 移除基于工具链镜像启动的容器
- 保留 Qdrant 数据卷
- 不删除工具链镜像

`scripts/task-harness-clean`：

- 停止基础设施
- 删除数据卷
- 删除工具链容器
- 删除工具链镜像
- 断开 `agent-network` 上的残留端点，然后移除网络
- 检查是否还有残留容器

## 多实例设计

每次 `harness-up` 或 `harness-shell` 都会通过 `docker run --rm` 创建一个独立工具链容器。

不同项目目录可以同时运行：

```bash
cd ~/projects/agent-a
mise run harness-up
```

```bash
cd ~/projects/agent-b
mise run harness-shell
```

两个容器会分别挂载各自项目目录到 `/workspace`，但共享同一个 `agent-network`，因此都可以访问：

- `agent-redis`
- `agent-qdrant`

默认端口发布会占用宿主机 `127.0.0.1:8000-8099`。如果多个工具链容器需要同时运行并对宿主机开放服务，应为后启动的容器设置不同的 `HARNESS_PORT_RANGE`，或设置 `HARNESS_PUBLISH_PORTS=0` 关闭端口发布。需要完整 `8000-9999` 窗口时，可以显式设置 `HARNESS_PORT_RANGE=8000-9999`。

## 直接使用 Docker image

普通用户不推荐直接使用 `docker run`，因为会绕过 `scripts/toolchain` 提供的环境变量、认证、缓存和网络处理。

如需排查镜像本身，可以手动运行：

```bash
docker run --rm -it \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  -e HOST_USER="$(id -un)" \
  -v "$PWD:/workspace" \
  -w /workspace \
  ai-dev:latest \
  bash
```

执行一次性命令：

```bash
docker run --rm \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  -e HOST_USER="$(id -un)" \
  -v "$PWD:/workspace" \
  -w /workspace \
  ai-dev:latest \
  python --version
```

更推荐使用：

```bash
scripts/toolchain shell .
scripts/toolchain run . python --version
```

## 设计边界

当前项目关注的是本地 AI Agent 开发环境，不负责：

- 部署生产环境
- 管理线上密钥
- 替代项目自身依赖管理
- 替代业务项目的测试和发布流程

它的核心目标是让用户在 Mac 上稳定、快速、可重复地进入一个准备好的开发环境。
