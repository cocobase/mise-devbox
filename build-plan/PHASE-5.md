# Phase 5: 工具链安装与 pnpm 策略调整

## 目标
利用 mise 安装项目所需的 Node.js, Python 和 UV，并采用稳定的 pnpm 安装策略。

## 详细计划
1.  **工具列表同步**：
    *   读取 `docker/mise-global.toml` 或 `.mise.toml`。
2.  **pnpm 优化**：
    *   在国内镜像模式下，通过脚本或 sed 将 `pnpm` 改为 `"npm:pnpm"`。
    *   **原理**：`npm:pnpm` 会通过 npm registry 安装，国内镜像同步极其完整。
3.  **批量并行安装**：
    *   执行 `mise install`（利用之前配置好的 Settings 镜像）。
    *   执行 `mise reshim` 确保路径刷新。

## Checklist
- [ ] `mise install` 过程是否显示正在从国内镜像地址（如 npmmirror, ustc）下载？
- [ ] Node.js, Python, pnpm, uv 是否均已安装成功？
- [ ] `pnpm` 命令在终端中是否可用？

## 验证方法
进入容器执行：
```bash
mise ls
node -v
python -v
pnpm -v
uv --version
```
确认所有版本号与 `.mise.toml` 中定义的匹配。
