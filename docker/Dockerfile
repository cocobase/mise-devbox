# syntax=docker/dockerfile:1
ARG USE_CHINA_MIRROR=false
ARG APT_MIRROR_NAME=aliyun
ARG NPM_REGISTRY=https://registry.npmmirror.com/
ARG MISE_VERSION=2025.2.1
ARG GH_VERSION=2.93.0

# ==========================================
# Stage 1: Base - Common setup & Non-root user
# ==========================================
FROM ubuntu@sha256:786a8b558f7be160c6c8c4a54f9a57274f3b4fb1491cf65146521ae77ff1dc54 AS base

ARG USE_CHINA_MIRROR
ARG APT_MIRROR_NAME
ARG DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Global Mise Environment
ENV MISE_DATA_DIR=/opt/mise
ENV MISE_CONFIG_DIR=/opt/mise-config
ENV MISE_CACHE_DIR=/opt/mise-cache
ENV MISE_INSTALL_PATH=/usr/local/bin/mise
ENV MISE_YES=1
ENV MISE_HTTP_TIMEOUT=300
ENV PATH="${MISE_DATA_DIR}/shims:${PATH}"

# Create Non-root User (Noble image has a default 'ubuntu' user with UID 1000)
RUN touch /var/mail/ubuntu && chown ubuntu /var/mail/ubuntu \
    && userdel -r ubuntu \
    && useradd -m -s /bin/bash -u 1000 developer \
    && mkdir -p /opt/mise /opt/mise-config /opt/mise-cache /opt/toolchain \
    && chown -R developer:developer /opt/mise /opt/mise-config /opt/mise-cache /opt/toolchain

# Architecture Detection and Apt Mirror Logic
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$USE_CHINA_MIRROR" = "true" ]; then \
         case "$APT_MIRROR_NAME" in \
           aliyun)   MIRROR_BASE="mirrors.aliyun.com" ;; \
           tsinghua) MIRROR_BASE="mirrors.tuna.tsinghua.edu.cn" ;; \
           ustc)     MIRROR_BASE="mirrors.ustc.edu.cn" ;; \
           *)        echo "Error: Invalid APT_MIRROR_NAME: $APT_MIRROR_NAME"; exit 1 ;; \
         esac; \
         if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then \
           sed -i "s|http://archive.ubuntu.com/ubuntu/|http://$MIRROR_BASE/ubuntu/|g" /etc/apt/sources.list.d/ubuntu.sources; \
           sed -i "s|http://security.ubuntu.com/ubuntu/|http://$MIRROR_BASE/ubuntu/|g" /etc/apt/sources.list.d/ubuntu.sources; \
           sed -i "s|http://ports.ubuntu.com/ubuntu-ports/|http://$MIRROR_BASE/ubuntu-ports/|g" /etc/apt/sources.list.d/ubuntu.sources; \
         fi; \
         if [ -f /etc/apt/sources.list ]; then \
           sed -i "s|http://archive.ubuntu.com/ubuntu|http://$MIRROR_BASE/ubuntu|g" /etc/apt/sources.list; \
           sed -i "s|http://security.ubuntu.com/ubuntu|http://$MIRROR_BASE/ubuntu|g" /etc/apt/sources.list; \
           sed -i "s|http://ports.ubuntu.com/ubuntu-ports|http://$MIRROR_BASE/ubuntu-ports|g" /etc/apt/sources.list; \
         fi; \
       fi

# Install base packages
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# ==========================================
# Stage 2: Builder - Install tools & dependencies
# ==========================================
FROM base AS builder

ARG MISE_VERSION
ARG GH_VERSION

# Use cache mount for apt to speed up multiple builds
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        git build-essential pkg-config \
        libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
        libffi-dev liblzma-dev xz-utils unzip

# Install gh CLI (Dynamic Architecture + Checksum)
RUN ARCH=$(dpkg --print-architecture) \
    && case "$ARCH" in \
         amd64) GH_ARCH="amd64"; GH_CHECKSUM="02d1290eba130e0b896f3709ffff22e1c75a51475ddb70476a85abc6b5807af0" ;; \
         arm64) GH_ARCH="arm64"; GH_CHECKSUM="c55feb33684abba57e9909737340d5b39282257c0363e1edde6785ac4a413be7" ;; \
         *)     echo "Unsupported architecture: $ARCH"; exit 1 ;; \
       esac \
    && curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${GH_ARCH}.tar.gz" -o "/tmp/gh.tar.gz" \
    && echo "${GH_CHECKSUM} /tmp/gh.tar.gz" | sha256sum -c - \
    && tar -xz -f /tmp/gh.tar.gz -C /tmp \
    && install -m 755 "/tmp/gh_${GH_VERSION}_linux_${GH_ARCH}/bin/gh" /usr/local/bin/gh

# Reliable Mise Installation
RUN ARCH=$(dpkg --print-architecture) \
    && case "$ARCH" in \
         amd64) MISE_ARCH="linux-x64"; MISE_CHECKSUM="dfdfc43ddd109ec51c32bcd4539e21c60c72c316e784881077557b65f2b87bae" ;; \
         arm64) MISE_ARCH="linux-arm64"; MISE_CHECKSUM="b1627fa6cca12d0c35c9c5c5b17c4900277d855587b812f85e6dcc0851c88940" ;; \
         *)     echo "Unsupported architecture: $ARCH"; exit 1 ;; \
       esac \
    && curl -fsSL "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-${MISE_ARCH}" -o /usr/local/bin/mise \
    && echo "${MISE_CHECKSUM} /usr/local/bin/mise" | sha256sum -c - \
    && chmod +x /usr/local/bin/mise

# Toolchain Preparation
WORKDIR /opt/toolchain
COPY .mise.toml /opt/toolchain/.mise.toml
COPY docker/mise-global.toml /opt/mise-config/config.toml
COPY docker/mise-china.toml /opt/mise-config/config-china.toml

# Switch to developer for tool installation
USER developer
ARG USE_CHINA_MIRROR
ARG NPM_REGISTRY

RUN if [ "$USE_CHINA_MIRROR" = "true" ]; then \
      cp /opt/mise-config/config-china.toml /opt/mise-config/config.toml; \
      find /opt/toolchain /opt/mise-config -name "*.toml" -exec sed -i 's/pnpm = "11.2.2"/"npm:pnpm" = "11.2.2"/' {} +; \
      echo "registry=$NPM_REGISTRY" > ~/.npmrc; \
    fi

# Use cache mount for mise downloads to speed up subsequent builds
RUN --mount=type=cache,target=/opt/mise-cache,uid=1000,gid=1000,mode=0777 \
    mise trust /opt/toolchain/.mise.toml \
    && mise trust /opt/mise-config/config.toml \
    && mise install \
    && mise reshim

# ==========================================
# Stage 3: Runtime - Minimal image
# ==========================================
FROM base AS runtime

# Install only runtime essentials
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl xz-utils libssl3 sudo \
    && rm -rf /var/lib/apt/lists/*

# Copy tools from builder
COPY --from=builder /usr/local/bin/mise /usr/local/bin/mise
COPY --from=builder --chown=developer:developer /opt/mise /opt/mise
COPY --from=builder --chown=developer:developer /opt/mise-config /opt/mise-config
COPY --from=builder --chown=developer:developer /opt/toolchain /opt/toolchain

WORKDIR /workspace
COPY --chown=developer:developer docker/entrypoint.sh /usr/local/bin/toolchain-entrypoint
RUN chmod +x /usr/local/bin/toolchain-entrypoint

# Start as root so entrypoint.sh can match host UID/GID
USER root
ENTRYPOINT ["/usr/local/bin/toolchain-entrypoint"]
CMD ["bash"]

# ==========================================
# Stage 4: Dev - Enhanced for development
# ==========================================
FROM runtime AS dev

# Install dev tools
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        git openssh-client \
    && echo "developer ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
    && rm -rf /var/lib/apt/lists/*

# Copy gh from builder
COPY --from=builder /usr/local/bin/gh /usr/local/bin/gh

# Still start as root for entrypoint.sh
USER root
