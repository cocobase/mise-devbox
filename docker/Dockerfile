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

RUN curl https://mise.run | sh \
    && cp /root/.local/bin/mise /usr/local/bin/mise \
    && /root/.local/bin/mise --version

WORKDIR /opt/toolchain
COPY .mise.toml /opt/toolchain/.mise.toml

RUN /root/.local/bin/mise trust /opt/toolchain/.mise.toml \
    && /root/.local/bin/mise install \
    && /root/.local/bin/mise reshim \
    && mkdir -p /opt/mise-config /opt/mise-cache \
    && chmod -R a+rX /opt/mise \
    && chmod -R a+rwX /opt/mise-config /opt/mise-cache

COPY docker/entrypoint.sh /usr/local/bin/toolchain-entrypoint
RUN chmod +x /usr/local/bin/toolchain-entrypoint

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/toolchain-entrypoint"]
CMD ["bash"]
