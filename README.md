# AI 开发环境一键启动工具

这个项目可以帮你在 Mac 上快速准备一个统一的 AI 开发环境。第一次安装好之后，你只需要在自己的项目目录里运行一条命令，就能进入已经准备好的开发环境。

这个环境里已经包含常用工具：

- Python
- Node.js
- pnpm
- uv
- git
- GitHub CLI
- Redis
- Qdrant

你不需要先理解 Docker、镜像、网络或数据卷。先按下面步骤跑起来即可。

## 适合谁使用

这个工具适合：

- 想快速开始 AI Agent 项目的人
- 不想手动配置 Python、Node.js、Redis、Qdrant 的人
- 希望多个项目都使用同一套开发环境的人
- 希望环境可以启动、停止、清理，并且行为一致的人

## 第一次使用

### 1. 准备 Mac 环境

你需要先安装：

- Docker Desktop 或 Colima
- mise

### 2. 下载到固定目录

推荐把这个项目放到 `~/.ai-harness`，这样以后可以在任意项目目录使用。

```bash
git clone <repo-url> ~/.ai-harness
cd ~/.ai-harness
```

### 3. 检查环境

```bash
./scripts/check-host
```

如果缺少组件，命令会提示安装方法。

### 4. 安装全局命令

```bash
./scripts/install-global
```

安装完成后，你会得到一组 `harness-*` 命令。以后不需要每次进入 `~/.ai-harness` 目录。

### 5. 构建开发环境

第一次使用前，建议先运行环境检查与测速：

```bash
mise run harness-check
```

该命令会对你的宿主机进行画像并自动为国内用户配置镜像源加速。接着构建环境：

```bash
mise run harness-build
```

第一次构建可能需要几分钟。以后通常不需要重复构建。

### 6. 进入你的项目目录

例如：

```bash
cd ~/projects/my-ai-agent
```

如果项目目录还不存在：

```bash
mkdir -p ~/projects/my-ai-agent
cd ~/projects/my-ai-agent
```

### 7. 启动并进入开发环境

```bash
mise run harness-up
```

成功后，你会进入一个命令行环境。你的当前项目目录会出现在这个环境里的 `/workspace`。

## 每天怎么用

日常使用只需要这几步：

```bash
cd 你的项目目录
mise run harness-up
```

退出当前开发环境：

```bash
exit
```

停止后台服务：

```bash
mise run harness-down
```

## 常用命令

| 我想要 | 运行命令 |
|---|---|
| 检查本机环境是否可用 | `mise run harness-check` |
| 第一次构建开发环境 | `mise run harness-build` |
| 启动并进入开发环境 | `mise run harness-up` |
| 快速进入开发环境 | `mise run harness-shell` |
| 在开发环境里运行一次命令 | `mise run harness-run -- python --version` |
| 查看工具版本 | `mise run harness-versions` |
| 查看 Redis 和 Qdrant 日志 | `mise run harness-logs` |
| 查看项目里的 Agent 日志 | `mise run harness-agent-logs` |
| 停止后台服务，保留数据 | `mise run harness-down` |
| 彻底清理环境和数据 | `mise run harness-clean` |

注意：`harness-clean` 会删除数据和本地镜像。普通停止请优先使用 `harness-down`。

## 怎么判断已经成功

进入环境后，可以运行：

```bash
python --version
node --version
pnpm --version
uv --version
git --version
gh --version
```

如果这些命令都能输出版本号，说明开发工具已经可用。

也可以运行：

```bash
pwd
ls
```

如果 `pwd` 显示 `/workspace`，并且 `ls` 能看到你项目目录里的文件，说明项目目录已经正确进入开发环境。

## 我的文件在哪里

你的文件仍然保存在 Mac 原来的项目目录里。

当你运行：

```bash
cd ~/projects/my-ai-agent
mise run harness-up
```

工具会把这个目录带入开发环境。在开发环境里，它显示为：

```text
/workspace
```

你在 `/workspace` 里创建或修改的文件，会同步出现在 Mac 上的 `~/projects/my-ai-agent`。

## API Key 怎么配置

如果你的项目需要 OpenAI、Anthropic、Google 或其他服务的 API Key，请先把 Key 放到当前终端环境中。例如：

```bash
export OPENAI_API_KEY="你的 Key"
```

启动环境时，工具会把当前终端里常见 AI 服务的 API Key 带入开发环境。

如果你是在本仓库目录开发这个工具本身，也可以复制模板文件：

```bash
cp .env.example .env
```

## 停止和清理有什么区别

| 命令 | 作用 | 是否删除数据 |
|---|---|---|
| `exit` | 退出当前开发环境 | 否 |
| `mise run harness-down` | 停止后台服务，保留数据 | 否 |
| `mise run harness-clean` | 彻底清理容器、镜像、网络和数据 | 是 |

日常使用推荐：

```bash
mise run harness-down
```

只有在你想完全重来，或者需要释放更多本地资源时，再使用：

```bash
mise run harness-clean
```

## 在本仓库开发这个工具

如果你是在维护这个 Harness 项目本身，而不是在普通业务项目里使用它，可以在本仓库目录运行：

```bash
./scripts/check-host
docker build -t ai-dev:latest -f docker/Dockerfile .
./scripts/task-harness-up
```

这些脚本是本仓库的本地开发入口。普通使用者更推荐先运行 `./scripts/install-global`，再使用全局命令：

```bash
mise run harness-up
```

## 常见问题

### 提示 Docker daemon 不可访问

这通常表示 Docker 已安装，但还没有启动。

如果你使用 Docker Desktop：

```bash
open -a Docker
docker version
```

如果你使用 Colima：

```bash
colima start --runtime docker --cpu 4 --memory 8
docker version
```

### 提示找不到 `harness-up`

说明全局命令还没有安装，或 mise 没有加载配置。

先确认安装过：

```bash
~/.ai-harness/scripts/install-global
```

再确认配置文件存在：

```bash
ls ~/.config/mise/config.toml
```

### 提示镜像不存在

先构建环境：

```bash
mise run harness-build
```

也可以直接运行：

```bash
mise run harness-up
```

如果镜像不存在，启动脚本会尝试自动构建。

### 使用 Colima 时看不到项目文件

Colima 默认更适合挂载 `$HOME` 下面的目录。建议把项目放在：

```text
~/projects
```

避免放在 `/tmp` 等目录。

### 想重新来一遍

如果只是停止后台服务：

```bash
mise run harness-down
```

如果想彻底清理并重新构建：

```bash
mise run harness-clean
mise run harness-build
```

## 更多说明

普通使用者通常只需要阅读本 README。

如果你需要排查问题、理解清理策略或查看日志，请看：

- [运维与排障说明](docs/operations.md)

如果你需要了解底层实现、Docker 镜像、权限、挂载、网络和脚本设计，请看：

- [架构与实现说明](docs/architecture.md)
