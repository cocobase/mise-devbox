# Phase 2: 操作系统基础包 (apt) 优化

## 目标
替换 Ubuntu 系统的软件源，确保在无证书环境下依然能稳定、快速地安装基础工具。

## 详细计划
1.  **DEB822 格式适配**：
    *   针对 Ubuntu 24.04 的 `/etc/apt/sources.list.d/ubuntu.sources` 进行修改。
2.  **镜像替换逻辑**：
    *   若开启国内镜像，使用 `sed` 替换官方域名为镜像提供商域名。
    *   **关键点**：初始替换使用 `http` 协议，以防止因 `ca-certificates` 缺失导致的 SSL 握手失败。
3.  **最小化依赖安装**：
    *   通过替换后的源安装 `ca-certificates`, `curl`, `git` 以及构建 Node/Python 所需的底层库。
    *   安装完成后，若安全策略需要，可将源协议切回 `https`。

## Checklist
- [ ] 是否同时处理了 `archive.ubuntu.com` (amd64) 和 `ports.ubuntu.com` (arm64)？
- [ ] 初始安装是否避开了 `https` 校验问题？
- [ ] `apt-get clean` 是否被执行以减小体积？

## 验证方法
在构建过程中观察 `apt-get update` 的日志：
- 确认所有连接地址均指向选定的国内镜像（如 `mirrors.aliyun.com`）。
- 确认没有出现证书相关的警告或错误。
