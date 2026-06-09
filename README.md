# Mac AI Dev Toolchain

面向 Mac 本地开发的 Docker 工具链项目。它用 `mise` 作为本机任务入口，用 Docker 镜像封装 Python、Node.js、pnpm、uv、git、GitHub CLI 和 mise。Mise 是一个多合一的开发环境管理器，通过统一的 mise.toml 配置文件，集中化管理项目的开发工具版本、环境变量以及自动化运行任务。

目标场景：初始化 AI 驱动开发项目时，一条命令启动容器，挂载本地开发目录，然后直接使用统一版本的开发工具链。

## 目录

- [包含的工具](#包含的工具)
- [环境准备](#环境准备)
- [构建镜像](#构建镜像)
- [进入工具链容器](#进入工具链容器)
- [直接使用 Docker image](#直接使用-docker-image)
- [`/workspace` 目录说明](#workspace-目录说明)
- [常用任务](#常用任务)
- [AI-Agent Harness (新)](#ai-agent-harness-新)
- [项目结构](#项目结构)
- [设计说明](#设计说明)
- [常见问题](#常见问题)

## 包含的工具

v1 工具链包含：

- `mise`
- `python` 3.12
- `node` 22
- `pnpm`
- `uv`
- `git`
- `gh`

默认 Docker image 名称：

```text
ai-dev-toolchain:latest
```

## 环境准备

Mac 本机需要：

- `mise`
- Docker CLI
- 一个 Docker 运行时，二选一：
  - Docker Desktop
  - Colima

先运行检查脚本：

```bash
scripts/check-host
# 或
mise run check
```

检查项覆盖：
- `mise` 命令及版本
- `docker` CLI 及 Daemon 状态
- `docker compose` / `docker-compose` 可用性
- `homebrew` 提示性检查（非阻塞）

如果依赖缺失，脚本会按优先级打印安装和启动步骤。

### 方案 A：Colima

适合偏命令行、轻量化的本地容器环境。

```bash
brew install colima docker
colima start --runtime docker --cpu 4 --memory 8
docker version
```

### 方案 B：Docker Desktop

适合需要 GUI、内置管理界面或 Docker Desktop 生态能力的环境。

```bash
brew install --cask docker
open -a Docker
docker version
```

### 安装 mise

```bash
brew install mise
```

如果不使用 Homebrew：

```bash
curl https://mise.run | sh
```

zsh 用户安装后需要激活：

```bash
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
exec zsh
```

验证：

```bash
mise --version
```

## 构建镜像

在本项目根目录执行：

```bash
mise run check
mise run build
```

构建完成后查看镜像：

```bash
docker image ls ai-dev-toolchain
```

查看容器内工具版本：

```bash
mise run versions
```

预期会看到类似输出：

```text
mise: 2026.5.15 linux-arm64
python: Python 3.12.13
node: v22.22.3
pnpm: 11.2.2
uv: uv 0.11.16
git: git version 2.43.0
gh: gh version 2.x.x
```

## 进入工具链容器

把当前目录挂载为容器内 `/workspace`：

```bash
mise run shell
```

挂载指定项目目录：

```bash
mise run shell -- ~/project/dev-tool
```

进入容器后可以直接使用工具链：

```bash
python --version
node --version
pnpm --version
uv --version
git --version
gh --version
```

执行一次性命令：

```bash
mise run run -- ~/project/dev-tool python --version
mise run run -- ~/project/dev-tool node --version
mise run run -- ~/project/dev-tool pnpm --version
mise run run -- ~/project/dev-tool uv --version
mise run run -- ~/project/dev-tool git --version
mise run run -- ~/project/dev-tool gh --version
```

初始化一个新项目目录：

```bash
mkdir -p ~/project/dev-tool
mise run shell -- ~/project/dev-tool
```

## 直接使用 Docker image

`mise` 任务只是封装了 `docker run` 参数。如果不通过 `mise`，也可以直接运行镜像。

> 💡 建议优先使用 `mise run shell` / `mise run run`，因为 `scripts/toolchain` 会自动处理环境变量透传、身份认证挂载和工具缓存挂载。手动运行以下命令时这些配置不会生效。

把当前目录挂载为 `/workspace`：

```bash
docker run --rm -it \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  -e HOST_USER="$(id -un)" \
  -v "$PWD:/workspace" \
  -w /workspace \
  ai-dev-toolchain:latest \
  bash
```

挂载指定项目目录：

```bash
docker run --rm -it \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  -e HOST_USER="$(id -un)" \
  -v "$HOME/project/dev-tool:/workspace" \
  -w /workspace \
  ai-dev-toolchain:latest \
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
  ai-dev-toolchain:latest \
  python --version
```

## `/workspace` 目录说明

`/workspace` 是容器内路径，不是 Mac 本机固定目录。

镜像通过 `Dockerfile` 设置默认工作目录：

```dockerfile
WORKDIR /workspace
```

容器启动时，`entrypoint.sh` 会确保目录存在：

```bash
mkdir -p /workspace
```

真正的代码来自 Docker volume 挂载。例如：

```bash
mise run shell -- ~/project/dev-tool
```

等价于把本机目录：

```text
~/project/dev-tool
```

挂载到容器内：

```text
/workspace
```

## 常用任务

```bash
mise tasks
mise run check        # 宿主机环境自检（含 docker-compose 检测）
mise run build        # 构建工具链镜像
mise run versions     # 查看容器内工具版本
mise run shell        # 进入容器交互式 Shell
mise run run          # 在容器内执行一次性命令
mise run setup        # 安装本机/容器所需依赖
mise run up           # 启动完整 Harness（检查 → 基础设施 → 镜像 → 进入 Shell）
mise run down         # 停止基础设施并清理容器（保留数据卷）
mise run logs         # 查看基础设施日志
mise run agent-logs   # 查看 Agent 日志
mise run clean        # 深度清理（删除卷、网络、镜像）
```

## AI-Agent Harness (新)

项目现在支持一个最小化的 AI-Agent 开发环境 (Harness)。

### 1. 基础设施服务
通过 `docker-compose.yml` 提供了以下服务：
- **Redis**: 用于 Agent 的短期记忆和缓存。
- **Qdrant**: 用于向量存储和知识库 (RAG)。

启动基础设施：
```bash
mise run up
```

### 2. 工具链集成
`scripts/toolchain` 已更新，启动时会自动加入 `agent-network` 网络。
这意味着你在容器内可以通过服务名直接访问基础设施：
- Redis: `agent-redis:6379`
- Qdrant: `agent-qdrant:6333`

### 3. 开发起步 (Python/Node.js)
项目根目录已配置 `pyproject.toml` (uv) 和 `package.json` (pnpm)，包含常用的 AI 库 (LangChain, Qdrant client, Redis client)。

在容器内初始化：
```bash
mise run setup
```

### 4. 连通性测试
在宿主机运行冒烟测试验证环境：
```bash
python3 smoke_test.py
```

覆盖验证项：
- 容器内工具版本与 `.mise.toml` 一致
- 宿主机目录 ↔ `/workspace` 双向同步
- `up → down` 后无容器残留
- 标准 `down` 后 Qdrant 数据卷保留
- 深度 `clean` 后网络和镜像无残留
- 热启动计时（目标 ≤ 5s）

### 5. API Key 安全注入
为了保护敏感信息，我们采用以下流程：
1. **复制模板**：在根目录执行 `cp .env.example .env`。
2. **填写 Key**：编辑 `.env` 文件，填入你的 OpenAI/Anthropic 等 API Key（此文件已被 `.gitignore` 忽略）。
3. **自动加载**：`mise` 会自动加载 `.env` 中的变量。
4. **容器透传**：`scripts/toolchain` 会自动识别并透传白名单环境变量到容器内部：
   - `OPENAI_*`, `ANTHROPIC_*`, `GOOGLE_*`, `LANGCHAIN_*`, `AZURE_*`
   - `MISTRAL_*`, `GROQ_*`, `COHERE_*`, `HF_*`
   - 任何以 `*_API_KEY` 结尾的变量
   - 基础设施变量：`REDIS_URL`, `QDRANT_HOST`, `QDRANT_PORT`

## 项目结构

```text
.
├── .dockerignore
├── .env.example
├── .mise.toml
├── README.md
├── docker-compose.yml
├── docker
│   ├── Dockerfile
│   ├── entrypoint.sh
│   └── mise-global.toml
├── plan.md
├── pyproject.toml
├── package.json
├── scripts
│   ├── check-host
│   ├── compose
│   ├── toolchain
│   └── lib
│       └── common.sh
├── smoke_test.py
└── user-story.md
```

## 设计说明

- 本机 `mise` 负责提供统一任务入口。
- Docker image 负责封装工具链版本和运行环境。
- 本地项目目录通过 volume 挂载到容器内 `/workspace`。
- 容器使用宿主机当前用户的 UID/GID 运行，避免在本机项目目录生成 root 拥有的文件。
- 镜像内置 `/opt/mise-config/config.toml` 作为全局工具版本配置，所以挂载的项目目录即使没有 `.mise.toml`，也能直接使用 `python`、`node`、`pnpm` 和 `uv`。
- `gh` 直接从 GitHub Release 下载安装到镜像中，运行时如需访问私有仓库或创建 PR，会在启动时自动挂载宿主机的 `~/.config/gh` 配置，或可在容器内执行 `gh auth login`。
- 容器启动时会自动 trust `/workspace/.mise.toml` 或 `/workspace/mise.toml`，避免挂载项目自己的 mise 配置时报未信任错误。
- `scripts/toolchain` 负责封装 `docker run` 的 UID/GID、volume、工作目录和 image 参数，同时自动透传白名单环境变量、身份认证配置和工具缓存。
- `scripts/compose` 是 docker compose 的包装器，自动检测并使用 `docker compose` (v2 插件) 或 `docker-compose` (v1 独立命令)，屏蔽版本差异。

## 常见问题

### Docker daemon 不可访问

错误示例：

```text
Docker CLI is installed, but Docker daemon is not reachable.
```

这表示 `docker` 命令存在，但 Docker 运行时没有启动。

使用 Colima：

```bash
colima start --runtime docker --cpu 4 --memory 8
docker version
```

使用 Docker Desktop：

```bash
open -a Docker
docker version
```

### 镜像不存在

如果运行容器时提示找不到 `ai-dev-toolchain:latest`，先构建镜像：

```bash
mise run build
```

### mise trust 错误

如果看到 mise trust 相关错误，通常是因为容器内用户 home 目录权限问题。镜像的 `entrypoint.sh` 已自动处理 `/workspace/.mise.toml` 的 trust，并确保 home 目录权限正确。如果仍报错，先确认镜像已用最新代码重新构建：

```bash
mise run build
mise run versions
```

### 清理镜像

```bash
mise run clean
```

`clean` 是**深度清理**，会：
- 停止并删除基础设施服务及其数据卷
- 删除所有 toolchain 容器
- 删除本地 `ai-dev-toolchain:latest` 镜像
- 移除 `agent-network` 网络
- 验证无残留

如果只是临时停止服务并保留数据，请使用 `mise run down`。
