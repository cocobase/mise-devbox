FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

ENV MISE_DATA_DIR=/opt/mise
ENV MISE_CONFIG_DIR=/opt/mise-config
ENV MISE_CACHE_DIR=/opt/mise-cache
ENV MISE_YES=1
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

RUN mkdir -p -m 755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && mkdir -p -m 755 /etc/apt/sources.list.d \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

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
    && chmod -R a+rX /opt/mise \
    && chmod -R a+rwX /opt/mise-config /opt/mise-cache

COPY docker/entrypoint.sh /usr/local/bin/toolchain-entrypoint
RUN chmod +x /usr/local/bin/toolchain-entrypoint

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/toolchain-entrypoint"]
CMD ["bash"]
