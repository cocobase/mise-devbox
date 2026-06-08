#!/usr/bin/env bash
set -euo pipefail

HOST_UID="${HOST_UID:-1000}"
HOST_GID="${HOST_GID:-1000}"
HOST_USER="${HOST_USER:-developer}"

# --- Fast path: skip useradd/groupadd if the exact user already exists ---
if id -u "${HOST_USER}" >/dev/null 2>&1; then
  existing_uid="$(id -u "${HOST_USER}")"
  existing_gid="$(id -g "${HOST_USER}")"
  if [[ "${existing_uid}" == "${HOST_UID}" ]] && [[ "${existing_gid}" == "${HOST_GID}" ]]; then
    # User already matches; skip creation entirely
    :
  else
    # Name collision with different UID/GID: create a fallback user
    HOST_USER="dev${HOST_UID}"
    useradd \
      --uid "${HOST_UID}" \
      --gid "${HOST_GID}" \
      --create-home \
      --shell /bin/bash \
      "${HOST_USER}" >/dev/null 2>&1 || true
  fi
else
  # Ensure group exists
  if ! getent group "${HOST_GID}" >/dev/null 2>&1; then
    groupadd --gid "${HOST_GID}" "${HOST_USER}" >/dev/null 2>&1 || true
  fi

  # Create user
  useradd \
    --uid "${HOST_UID}" \
    --gid "${HOST_GID}" \
    --create-home \
    --shell /bin/bash \
    "${HOST_USER}" >/dev/null 2>&1 || true
fi

mkdir -p /workspace
chown -R "${HOST_UID}:${HOST_GID}" /workspace 2>/dev/null || true
mkdir -p /opt/mise-config /opt/mise-cache
chmod -R a+rwX /opt/mise-config /opt/mise-cache 2>/dev/null || true

export MISE_DATA_DIR=/opt/mise
export MISE_CONFIG_DIR=/opt/mise-config
export MISE_CACHE_DIR=/opt/mise-cache
export PATH="/opt/mise/shims:/usr/local/bin:${PATH}"

for config_file in /workspace/.mise.toml /workspace/mise.toml; do
  if [[ -f "${config_file}" ]]; then
    sudo \
      --set-home \
      --user "#${HOST_UID}" \
      env \
      "MISE_DATA_DIR=${MISE_DATA_DIR}" \
      "MISE_CONFIG_DIR=${MISE_CONFIG_DIR}" \
      "MISE_CACHE_DIR=${MISE_CACHE_DIR}" \
      "PATH=${PATH}" \
      mise trust "${config_file}" >/dev/null 2>&1 || true
  fi
done

exec sudo \
  --set-home \
  --user "#${HOST_UID}" \
  env \
  "MISE_DATA_DIR=${MISE_DATA_DIR}" \
  "MISE_CONFIG_DIR=${MISE_CONFIG_DIR}" \
  "MISE_CACHE_DIR=${MISE_CACHE_DIR}" \
  "PATH=${PATH}" \
  "$@"
