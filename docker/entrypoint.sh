#!/usr/bin/env bash
set -euo pipefail

_ep_ms() { echo $(( $(date +%s%3N) )); }
T0=$(_ep_ms)
_ep_step() { printf '[entrypoint-timing] %6dms  %s\n' "$(( $(_ep_ms) - T0 ))" "$1" >&2; }

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
_ep_step "user-setup"

mkdir -p /workspace
# Only chown the workspace mount point itself, not the host files inside it.
# Recursive chown on macOS/virtiofs mounts can be extremely slow and is usually
# unnecessary because the host files are already owned by the current user.
if [[ "$(stat -c '%u:%g' /workspace 2>/dev/null || echo '0:0')" != "${HOST_UID}:${HOST_GID}" ]]; then
  chown "${HOST_UID}:${HOST_GID}" /workspace 2>/dev/null || true
fi
_ep_step "workspace"

mkdir -p /opt/mise-config /opt/mise-cache /opt/mise-cache/state
chmod -R a+rwX /opt/mise-config /opt/mise-cache 2>/dev/null || true
_ep_step "permissions"

# Ensure the user home directory exists so tools like mise
# can write config/cache files under ~/.local.
# Ownership is already correct from useradd --create-home above.
user_home="/home/${HOST_USER}"
mkdir -p "${user_home}"
_ep_step "home-dir"

export MISE_DATA_DIR=/opt/mise
export MISE_CONFIG_DIR=/opt/mise-config
export MISE_CACHE_DIR=/opt/mise-cache
export XDG_CONFIG_HOME="${MISE_CONFIG_DIR}"
export XDG_DATA_HOME="${MISE_DATA_DIR}"
export XDG_CACHE_HOME="${MISE_CACHE_DIR}"
export XDG_STATE_HOME="/opt/mise-cache/state"
export PATH="/opt/mise/shims:/usr/local/bin:${PATH}"

# Collect API key env vars so they survive the sudo barrier below
_api_env=()
for _v in $(compgen -v); do
  case "${_v}" in
    *_API_KEY|OPENAI_*|ANTHROPIC_*|GOOGLE_*|LANGCHAIN_*|AZURE_*|MISTRAL_*|GROQ_*|COHERE_*|HF_*)
      [[ -n "${!_v:-}" ]] && _api_env+=("${_v}=${!_v}")
      ;;
  esac
done

for config_file in /workspace/.mise.toml /workspace/mise.toml; do
  if [[ -f "${config_file}" ]]; then
    sudo \
      --set-home \
      --user "#${HOST_UID}" \
      env \
      "HOME=${user_home}" \
      "MISE_DATA_DIR=${MISE_DATA_DIR}" \
      "MISE_CONFIG_DIR=${MISE_CONFIG_DIR}" \
      "MISE_CACHE_DIR=${MISE_CACHE_DIR}" \
      "XDG_CONFIG_HOME=${XDG_CONFIG_HOME}" \
      "XDG_DATA_HOME=${XDG_DATA_HOME}" \
      "XDG_CACHE_HOME=${XDG_CACHE_HOME}" \
      "XDG_STATE_HOME=${XDG_STATE_HOME}" \
      "${_api_env[@]}" \
      "PATH=${PATH}" \
      mise trust "${config_file}" >/dev/null 2>&1 || true
  fi
done
_ep_step "mise-trust"

exec sudo \
  --set-home \
  --user "#${HOST_UID}" \
  env \
  "HOME=${user_home}" \
  "MISE_DATA_DIR=${MISE_DATA_DIR}" \
  "MISE_CONFIG_DIR=${MISE_CONFIG_DIR}" \
  "MISE_CACHE_DIR=${MISE_CACHE_DIR}" \
  "XDG_CONFIG_HOME=${XDG_CONFIG_HOME}" \
  "XDG_DATA_HOME=${XDG_DATA_HOME}" \
  "XDG_CACHE_HOME=${XDG_CACHE_HOME}" \
  "XDG_STATE_HOME=${XDG_STATE_HOME}" \
  "${_api_env[@]}" \
  "PATH=${PATH}" \
  "$@"
