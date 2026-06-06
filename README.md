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
```

如果依赖缺失或 Docker daemon 未启动，脚本会打印安装和启动步骤。

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
mise run check
mise run build
mise run versions
mise run shell
mise run shell -- ~/project/dev-tool
mise run run -- . python --version
mise run clean
```

## 项目结构

```text
.
├── .dockerignore
├── .mise.toml
├── README.md
├── docker
│   ├── Dockerfile
│   └── entrypoint.sh
└── scripts
    ├── check-host
    └── toolchain
```

## 设计说明

- 本机 `mise` 负责提供统一任务入口。
- Docker image 负责封装工具链版本和运行环境。
- 本地项目目录通过 volume 挂载到容器内 `/workspace`。
- 容器使用宿主机当前用户的 UID/GID 运行，避免在本机项目目录生成 root 拥有的文件。
- 镜像内置 `/opt/mise-config/config.toml` 作为全局工具版本配置，所以挂载的项目目录即使没有 `.mise.toml`，也能直接使用 `python`、`node`、`pnpm` 和 `uv`。
- `gh` 通过 GitHub CLI 官方 apt 仓库安装在镜像中，运行时如需访问私有仓库或创建 PR，需要在容器内执行 `gh auth login` 或挂载已有认证配置。
- 容器启动时会自动 trust `/workspace/.mise.toml` 或 `/workspace/mise.toml`，避免挂载项目自己的 mise 配置时报未信任错误。
- `scripts/toolchain` 负责封装 `docker run` 的 UID/GID、volume、工作目录和 image 参数。

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

如果看到 mise trust 相关错误，先确认镜像已经用最新代码重新构建：

```bash
mise run build
mise run versions
```

### 清理镜像

```bash
mise run clean
```
