# Docker 构建下载源优化方案

> 目标：在保持默认配置不变的前提下，提供可一键启用的国内镜像方案，显著缩短 `docker build` 时间并提升稳定性。

---

## 1. 当前 Dockerfile 的下载源梳理

| 步骤 | 当前来源 | 用途 | 当前风险 |
|------|----------|------|----------|
| `apt-get update` | `archive.ubuntu.com` / `security.ubuntu.com` | Ubuntu 系统依赖 | 国内访问慢、偶发超时 |
| GitHub CLI apt repo | `cli.github.com/packages` | 安装 `gh` | 依赖 GitHub 域名，国内不稳定 |
| `curl https://mise.run` | `mise.run`（脚本内部转向 GitHub Releases） | 安装 mise 本体 | 脚本+二进制均走 GitHub |
| `mise install python` | `astral-sh/python-build-standalone` GitHub Releases | Python 3.12.13 | GitHub 大文件下载慢/中断 |
| `mise install node` | `nodejs.org/dist` | Node.js | 官方源在国内速度一般 |
| `mise install pnpm` | `pnpm/pnpm` GitHub Releases（aqua backend） | pnpm 11.2.2 | GitHub 下载 |
| `mise install uv` | `astral-sh/uv` GitHub Releases（aqua backend） | uv 0.11.16 | GitHub 下载 |

### 1.1 实测延迟（当前网络环境）

```text
archive.ubuntu.com InRelease                  2.025s
mirrors.aliyun.com InRelease                  0.273s   ← 最快
mirrors.tuna.tsinghua.edu.cn InRelease        0.693s
mirrors.ustc.edu.cn InRelease                 4.812s

https://cli.github.com/packages/keyring       0.393s   ← 可接受
https://mise.run                                1.763s
https://github.com/jdx/mise/releases/latest     0.655s

nodejs.org/dist/v22.22.3/...                  0.895s
npmmirror.com/mirrors/node/v22.22.3/...       0.597s   ← 国内更快
mirrors.ustc.edu.cn/node/...                  0.276s   ← 但目录结构旧，不推荐

GitHub uv release (0.11.16)                  15.0s timeout
releases.astral.sh/github/uv/0.11.16          0.919s   ← 官方国内友好镜像
USTC python-build-standalone/20260610         0.600s   ← 有 3.12.13
```

> 结论：**apt → 阿里云、node → npmmirror、uv → releases.astral.sh、python → USTC github-release** 是当前实测最快的组合。

---

## 2. 推荐方案：可开关的国内镜像层

### 2.1 设计原则

1. **默认不变**：不开启镜像时，Dockerfile 行为与现在完全一致，避免影响海外用户/CI。
2. **一个开关**：通过 `--build-arg USE_CHINA_MIRROR=true` 一键启用。
3. **分层配置**：镜像设置集中在 `docker/mise-china.toml`，不与 `mise-global.toml` 强耦合。
4. **可替换**：每个镜像源都暴露为 `ARG`，方便团队根据实际情况调整。

### 2.2 镜像选择矩阵

| 组件 | 推荐国内源 | 备用源 | 说明 |
|------|-----------|--------|------|
| Ubuntu apt | `mirrors.aliyun.com/ubuntu` | Tsinghua / USTC | 实测最快、同步及时 |
| mise 本体 | `npm install -g mise` via `registry.npmmirror.com` | GitHub direct | npm 源在国内更稳定 |
| Node.js | `https://npmmirror.com/mirrors/node/` | `https://mirrors.tuna.tsinghua.edu.cn/nodejs-release/` | mise 原生支持 `node.mirror_url` |
| Python | `https://mirrors.ustc.edu.cn/github-release/astral-sh/python-build-standalone/` | GitHub direct | 通过 `url_replacements` 重写 |
| pnpm | `npm:pnpm` backend + `registry.npmmirror.com` | GitHub aqua | 避免 GitHub release 无镜像问题 |
| uv | `https://releases.astral.sh/github` | GitHub direct | Astral 官方国内加速镜像 |
| GitHub CLI apt | `cli.github.com/packages` | — | 实测速度可接受，暂不改 |

---

## 3. 拟修改内容

### 3.1 新增 `docker/mise-china.toml`

```toml
# 国内镜像下 mise 工具下载源配置
# 通过 Dockerfile 中 MISE_CONFIG_DIR 指向此文件

[settings]
# node 官方 mirror_url 设置
node.mirror_url = "https://npmmirror.com/mirrors/node/"

# GitHub release 重写
[settings.url_replacements]
# uv: 使用 Astral 官方国内友好 releases 镜像
"regex:^https://github\\.com/astral-sh/uv/releases/download/([^/]+)/(.+)" = "https://releases.astral.sh/github/uv/releases/download/$1/$2"

# python-build-standalone: 使用 USTC github-release 镜像
"regex:^https://github\\.com/astral-sh/python-build-standalone/releases/download/([^/]+)/(.+)" = "https://mirrors.ustc.edu.cn/github-release/astral-sh/python-build-standalone/$1/$2"
```

### 3.2 新增 `docker/sources.aliyun.sources`

Ubuntu 24.04 使用 DEB822 格式：

```
Types: deb
URIs: https://mirrors.aliyun.com/ubuntu/
Suites: noble noble-updates noble-backports noble-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
```

### 3.3 Dockerfile 改造要点

```dockerfile
# ------------------------------------------------------------------
# 镜像开关（默认关闭，保持原行为）
# ------------------------------------------------------------------
ARG USE_CHINA_MIRROR=false
ARG APT_MIRROR=aliyun
ARG NPM_REGISTRY=https://registry.npmmirror.com/
ARG NODE_MIRROR=https://npmmirror.com/mirrors/node/
ARG UV_MIRROR_BASE=https://releases.astral.sh/github
ARG PYTHON_MIRROR_BASE=https://mirrors.ustc.edu.cn/github-release/astral-sh/python-build-standalone

# ------------------------------------------------------------------
# 1. 替换 apt 源（可选）
# ------------------------------------------------------------------
RUN if [ "$USE_CHINA_MIRROR" = "true" ]; then \
      case "$APT_MIRROR" in \
        aliyun) MIRROR="https://mirrors.aliyun.com/ubuntu/" ;; \
        tsinghua) MIRROR="https://mirrors.tuna.tsinghua.edu.cn/ubuntu/" ;; \
        ustc) MIRROR="https://mirrors.ustc.edu.cn/ubuntu/" ;; \
      esac; \
      if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then \
        sed -i "s|http://archive.ubuntu.com/ubuntu/|$MIRROR|g; s|http://security.ubuntu.com/ubuntu/|$MIRROR|g; s|https://archive.ubuntu.com/ubuntu/|$MIRROR|g; s|https://security.ubuntu.com/ubuntu/|$MIRROR|g" /etc/apt/sources.list.d/ubuntu.sources; \
      else \
        cp /etc/apt/sources.list /etc/apt/sources.list.bak; \
        sed -i "s|http://archive.ubuntu.com/ubuntu|$MIRROR|g; s|http://security.ubuntu.com/ubuntu|$MIRROR|g; s|https://archive.ubuntu.com/ubuntu|$MIRROR|g; s|https://security.ubuntu.com/ubuntu|$MIRROR|g" /etc/apt/sources.list; \
      fi; \
    fi

# ------------------------------------------------------------------
# 2. 安装 mise（国内使用 npm 源，避免 GitHub）
# ------------------------------------------------------------------
RUN if [ "$USE_CHINA_MIRROR" = "true" ]; then \
      # 先通过 npmmirror 下载一个临时 Node，仅用于 npm install mise
      NODE_VERSION="22.22.3"; \
      ARCH=$(dpkg --print-architecture); \
      case "$ARCH" in \
        amd64) NODE_ARCH="x64" ;; \
        arm64) NODE_ARCH="arm64" ;; \
      esac; \
      mkdir -p /tmp/node-bootstrap; \
      curl -fsSL "https://npmmirror.com/mirrors/node/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" \
        | tar -xJf - -C /tmp/node-bootstrap --strip-components=1 --no-same-owner; \
      export PATH="/tmp/node-bootstrap/bin:$PATH"; \
      npm config set registry "$NPM_REGISTRY"; \
      npm install -g mise; \
      cp "$(which mise)" /usr/local/bin/mise; \
      rm -rf /tmp/node-bootstrap; \
    else \
      curl https://mise.run | sh; \
      cp /root/.local/bin/mise /usr/local/bin/mise; \
    fi

# ------------------------------------------------------------------
# 3. 配置 mise 国内镜像
# ------------------------------------------------------------------
COPY docker/mise-china.toml /opt/mise-config/config-china.toml
RUN if [ "$USE_CHINA_MIRROR" = "true" ]; then \
      cp /opt/mise-config/config-china.toml /opt/mise-config/config.toml; \
    fi

# ------------------------------------------------------------------
# 4. pnpm 改用 npm backend（国内 npm 源有完整镜像）
# ------------------------------------------------------------------
# 在 mise-global.toml / mise-china.toml 中：
# [tools]
# python = "3.12.13"
# node = "22.22.3"
# "npm:pnpm" = "11.2.2"   # 替代 pnpm = "11.2.2"
# uv = "0.11.16"
```

### 3.4 `docker/mise-global.toml` 同步调整

当前：

```toml
[tools]
python = "3.12.13"
node = "24.16.0"
pnpm = "11.2.2"
uv = "0.11.16"
```

为配合国内 npm 源，建议在国内配置文件中改为：

```toml
[tools]
python = "3.12.13"
node = "24.16.0"
"npm:pnpm" = "11.2.2"
uv = "0.11.16"
```

> 注：`.mise.toml` 项目级配置中的 `pnpm = "11.2.2"` 同样建议改为 `"npm:pnpm" = "11.2.2"`；mise 的 npm backend 需要 Node 先安装，mise 会自动处理依赖顺序。

---

## 4. 构建命令

### 4.1 国内网络

```bash
docker build \
  --build-arg USE_CHINA_MIRROR=true \
  --build-arg APT_MIRROR=aliyun \
  -t ai-dev-toolchain:latest \
  -f docker/Dockerfile .
```

### 4.2 海外/默认

```bash
docker build -t ai-dev-toolchain:latest -f docker/Dockerfile .
```

---

## 5. 验证计划

构建完成后在容器内执行：

```bash
mise run versions
# 应输出对应版本号

# 验证各工具实际来源
mise ls --tree
mise settings node.mirror_url    # 国内应显示 npmmirror
mise settings url_replacements   # 国内应显示 uv/python 重写规则
```

---

## 6. 风险与注意事项

| 风险 | 说明 | 缓解 |
|------|------|------|
| 镜像同步延迟 | 国内镜像可能滞后于官方 Release | 保留 `--build-arg` 开关，失败时切回官方 |
| USTC 镜像版本不全 | 某些 Python build 日期可能缺失 | 失败时自动/手动回退 GitHub；或定期更新 pinned 版本 |
| npm backend pnpm 行为差异 | `npm:pnpm` 与 aqua `pnpm` 安装路径不同 | 功能一致，仅内部存储路径变化；需验证 `pnpm --version` |
| `mise-china.toml` 与默认配置分叉 | 两个 config 文件需同步版本号 | 在 README/AGENTS.md 中说明维护责任 |
| 企业内网无法访问任何公网镜像 | 需要私有镜像 | 所有 `ARG` 均可替换为内部 Nexus/Artifactory 地址 |

---

## 7. 建议的实施步骤

1. 创建 `docker/mise-china.toml` 和 `docker/sources.aliyun.sources`。
2. 改造 `docker/Dockerfile`，加入 `USE_CHINA_MIRROR` 等 `ARG` 与条件分支。
3. 在国内/海外两种网络环境下分别跑 `mise run build` 对比耗时。
4. 根据实测结果把 `mise-global.toml` 中的 `pnpm` 改为 `"npm:pnpm"`（若验证通过）。
5. 更新 `README.md` 的“构建镜像”章节，补充国内镜像用法。
