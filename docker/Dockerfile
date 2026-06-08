FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG GH_VERSION=2.93.0
ARG GH_ARCH=arm64

ENV MISE_DATA_DIR=/opt/mise
ENV MISE_CONFIG_DIR=/opt/mise-config
ENV MISE_CACHE_DIR=/opt/mise-cache
ENV MISE_YES=1
ENV MISE_HTTP_TIMEOUT=300
ENV PATH="/opt/mise/shims:/usr/local/bin:${PATH}"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        build-essential \
        pkg-config \
        libssl-dev \
        zlib1g-dev \
        libbz2-dev \
        libreadline-dev \
        libsqlite3-dev \
        libffi-dev \
        liblzma-dev \
        xz-utils \
        unzip \
        sudo \
    && rm -rf /var/lib/apt/lists/*

# Install gh CLI directly from GitHub release (faster than apt repo in some regions)
RUN curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${GH_ARCH}.tar.gz" \
    | tar -xz -C /tmp \
    && install -m 755 /tmp/gh_${GH_VERSION}_linux_${GH_ARCH}/bin/gh /usr/local/bin/gh \
    && rm -rf /tmp/gh_* \
    && gh --version

RUN curl https://mise.run | sh \
    && cp /root/.local/bin/mise /usr/local/bin/mise \
    && /root/.local/bin/mise --version

WORKDIR /opt/toolchain
RUN mkdir -p /opt/mise-config /opt/mise-cache
COPY .mise.toml /opt/toolchain/.mise.toml
COPY docker/mise-global.toml /opt/mise-config/config.toml

RUN /root/.local/bin/mise trust /opt/toolchain/.mise.toml \
    && /root/.local/bin/mise trust /opt/mise-config/config.toml \
    && /root/.local/bin/mise install \
    && /root/.local/bin/mise reshim \
    && chmod -R a+rwx /opt/mise \
    && chmod -R a+rwX /opt/mise-config /opt/mise-cache

COPY docker/entrypoint.sh /usr/local/bin/toolchain-entrypoint
RUN chmod +x /usr/local/bin/toolchain-entrypoint

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/toolchain-entrypoint"]
CMD ["bash"]
