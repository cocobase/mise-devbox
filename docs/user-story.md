# 用户故事

目标：构建一个简洁已用的，开发 AI Agent 的 Harness 环境。这里列出了普通开发者非常容易地使用这个 harness 系统的常见任务。

## 工具链软件的定义

- homebrew
- mise
- node
- python
- uv
- git
- gh
- pnpm
- redis

## 用户使用场景

1. 开始工作，启动系统 `mise run harness-up`: 启动了 docker 容器，这个容器中已经运行了必要的工具链软件。同时加载了当前的目录作为工作目录。自动进入容器环境。

2. 用户在一个新安装操作系统的机器中，需要进行宿主机环境自检命令 `mise run harness-check`：确保 homebrew、mise、docker、colima（若适用）处于就绪状态。如果不存在则提示安装方法。同时会自动配置最佳速度的下载源（实时测速）。

3. 在工作过程中，使用 `mise run harness-logs` 来显示日志文件的最新内容。使用 `mise run harness-down` 来停止服务，关闭 docker 容器并且释放本地资源。

## 达成目标的评估

1. 执行 `mise run harness-up` 后，是否在 5 秒内自动进入容器 Shell。容器内 python, node, uv, pnpm 可用且版本正确。当前宿主机目录已正确挂载到 `/workspace`。

2. `mise run harness-down` 执行后，`docker ps -a` 为空。运行 `docker network ls` 和 `docker ps` 确保无残留。
