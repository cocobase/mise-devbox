# ISSUE-1：对 `MIRROR_PROPOSAL.md` 国内镜像方案的改进意见

## 背景

在执行 `MIRROR_PROPOSAL.md` 的过程中，基于实际的 arm64（Apple Silicon + Colima）构建环境验证了该方案。虽然整体思路可行，但暴露出若干未在原文中充分考虑的细节问题。本文档将这些问题及对应的改进建议汇总，供后续修订参考。

## 问题与改进建议

| 问题 | 改进建议 | 理由 |
|------|----------|------|
| apt 源替换只考虑 `archive.ubuntu.com` / `security.ubuntu.com` | 明确增加对 `ports.ubuntu.com/ubuntu-ports` 的处理，并按架构区分 `ubuntu/`（amd64）与 `ubuntu-ports/`（arm64）镜像路径 | Ubuntu 24.04 arm64 容器实际使用 `ports.ubuntu.com/ubuntu-ports`，不替换则国内镜像对 arm64 失效 |
| apt 镜像使用 `https://` | 建议使用 `http://` 国内镜像，或先安装 `ca-certificates` 再切换 https | 基础镜像初始缺少 `ca-certificates`，https 源会导致证书校验失败、所有包无法下载 |
| mise 本体依赖 `npm install -g mise` | 改为从 GitHub Release 直接下载固定版本的 mise 二进制，并暴露 `MISE_DOWNLOAD_URL` 供企业内网覆盖 | 国内 npm 镜像（如 npmmirror）对 `@jdxcode/mise-linux-arm64` 等架构特定包同步不全，npm 安装会失败 |
| 未强调架构兼容性测试 | 在“验证计划”中明确要求分别在国内/海外、amd64/arm64 环境下验证 | 本次在 arm64 下连续踩坑，说明仅按 amd64 设计会遗漏大量问题 |
| 未固定工具版本或版本策略 | 增加“版本固定与回退策略”章节，说明 mise 版本固定原因及如何更新 | 固定版本可避免国内镜像同步延迟导致构建失败，但也需要定期维护 |
| 未提及构建磁盘空间 | 在“风险与注意事项”中增加“构建产物较大，需确保 Docker/Colima 有足够磁盘空间” | 本次最终因虚拟机磁盘不足导致镜像导出失败，环境空间是常被忽视的因素 |
| pnpm 改为 `npm:pnpm` 的时机 | 明确说明在国内模式下通过 Dockerfile 动态修改 `.mise.toml`，而非直接改默认配置 | 这样既能保持默认配置不变，又能在国内模式下实际生效，避免 `.mise.toml` 与 `mise-china.toml` 配置冲突 |

## 结论

`MIRROR_PROPOSAL.md` 的整体设计（默认不变、一键启用、分层配置、可替换 ARG）是合理的，但需要在以下两个方向补强：

1. **多架构兼容性**：Ubuntu apt 源和 mise 安装方式都必须同时考虑 amd64 与 arm64。
2. **基础镜像初始状态约束**：不能假设基础镜像已具备 `ca-certificates` 等证书工具，https 镜像源需要分阶段处理。

此外，建议将“npm 安装 mise”替换为更可靠的 GitHub Release 固定版本下载，并保留可覆盖的下载地址，以兼顾国内网络和企业私有镜像场景。
