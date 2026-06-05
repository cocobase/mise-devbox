# Mac AI Dev Toolchain

一个面向 Mac 本地开发的 Docker 工具链项目。它用 `mise` 串联常用开发工具，并把 Python、Node.js、pnpm、uv、git 封装到统一容器中。

目标场景：用户初始化 AI 驱动开发项目时，只需要一条命令启动容器并挂载本地开发目录，就能直接使用统一版本的工具链。

## 工具链

v1 包含：

- Python 3.12
- Node.js 22
- pnpm
- uv
- git
- mise

容器内默认工作目录是 `/workspace`，本机项目目录会挂载到这里。

默认镜像名：

```text
ai-dev-toolchain:latest
```

## 前置要求

Mac 本机需要安装：

- mise
- 一个 Docker 运行时：
  - Docker Desktop
  - 或 Colima + Docker CLI

先检查本机环境：

```bash
scripts/check-host
```

如果缺少依赖，脚本会打印安装步骤并要求先完成安装。

如果选择 Colima：

```bash
brew install colima docker
colima start --runtime docker --cpu 4 --memory 8
docker version
```

如果选择 Docker Desktop：

```bash
brew install --cask docker
open -a Docker
docker version
```

安装完成后，在本项目目录执行：

```bash
mise run check
mise run build
```

构建完成后，本机 Docker 里会得到镜像：

```bash
docker image ls ai-dev-toolchain
```

## 一键进入工具链

把当前目录作为开发目录挂载：

```bash
mise run shell
```

挂载指定项目目录：

```bash
mise run shell -- ~/projects/my-ai-app
```

执行一次性命令：

```bash
mise run run -- ~/projects/my-ai-app python --version
mise run run -- ~/projects/my-ai-app node --version
mise run run -- ~/projects/my-ai-app pnpm --version
mise run run -- ~/projects/my-ai-app uv --version
mise run run -- ~/projects/my-ai-app git --version
```

## 直接使用 Docker image

如果不通过 `mise` 任务，也可以直接使用构建好的 Docker image。

把当前目录挂载为容器内 `/workspace`：

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
  -v "$HOME/projects/my-ai-app:/workspace" \
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

`scripts/toolchain` 做的事情就是封装这些 `docker run` 参数，避免每次手写 UID/GID、volume 和工作目录。

## `/workspace` 是什么

`/workspace` 是容器内路径，不是 Mac 本机固定目录。

它在镜像里由 `Dockerfile` 设置为默认工作目录：

```dockerfile
WORKDIR /workspace
```

容器启动时，`entrypoint.sh` 会确保目录存在：

```bash
mkdir -p /workspace
```

真正的代码目录来自 Docker volume 挂载。例如：

```bash
mise run shell -- ~/projects/my-ai-app
```

等价于把 Mac 本机的：

```text
~/projects/my-ai-app
```

挂载到容器内：

```text
/workspace
```

## 初始化一个 AI 开发项目

示例：

```bash
mkdir -p ~/projects/my-ai-app
mise run shell -- ~/projects/my-ai-app
```

进入容器后：

```bash
python --version
node --version
pnpm --version
uv --version
git --version
```

## 项目结构

```text
.
├── .mise.toml
├── docker
│   ├── Dockerfile
│   └── entrypoint.sh
├── scripts
│   ├── check-host
│   └── toolchain
└── README.md
```

## 设计说明

- 本机 `mise` 负责提供统一入口，不直接污染用户项目。
- Docker 镜像负责封装工具链版本和运行环境。
- 本地项目目录通过 volume 挂载到 `/workspace`。
- 容器使用当前宿主用户的 UID/GID 运行，避免在本机项目目录生成 root 拥有的文件。
- 容器启动时会自动 trust `/workspace/.mise.toml` 或 `/workspace/mise.toml`，避免挂载项目自己的 mise 配置时报未信任错误。

## 常用任务

```bash
mise tasks
mise run check
mise run build
mise run shell
mise run run -- . python --version
mise run clean
```

## 常见问题

如果看到：

```text
Docker CLI is installed, but Docker daemon is not reachable.
```

说明 `docker` 命令存在，但 Docker 运行时还没有启动。

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

如果看到 mise trust 相关错误，先确认镜像已经用最新代码重新构建：

```bash
mise run build
mise run versions
```
