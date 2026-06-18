# Phase 3: 可靠的 Mise 本体安装

## 目标
绕过不可靠的安装脚本和同步不全的 npm 包镜像，通过直接下载二进制文件实现 mise 的高可用安装。

## 详细计划
1.  **下载策略制定**：
    *   定义 `MISE_DOWNLOAD_URL_BASE` 变量，支持从 GitHub 或私有镜像源下载。
    *   根据架构（`x64`/`arm64`）拼接完整的二进制文件名。
2.  **二进制分发**：
    *   使用 `curl` 下载指定版本的压缩包。
    *   解压并将二进制文件放置到 `/usr/local/bin/mise`。
3.  **全局初始化**：
    *   执行 `mise --version` 验证。
    *   创建必要的配置目录 `/opt/mise-config` 并赋予适当权限。

## Checklist
- [ ] 是否固定了 `MISE_VERSION`？
- [ ] 是否支持通过 `ARG` 覆盖下载地址以适配极端的内网环境？
- [ ] 安装路径是否位于全局可寻址的 `PATH` 中？

## 验证方法
在构建完成后的镜像中运行：
```bash
docker run --rm test-phase-3 mise --version
```
检查输出的版本号是否与定义的 `MISE_VERSION` 一致。
