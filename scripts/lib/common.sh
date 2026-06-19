#!/usr/bin/env bash
# Shared utilities for the AI-Agent Harness toolchain scripts.
# Source this file from other scripts: source "$(dirname "$0")/lib/common.sh"

set -euo pipefail

# -----------------------------------------------------------------------------
# Colors
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Logging helpers
# -----------------------------------------------------------------------------
log_info()  { printf "${BLUE}ℹ️  %s${NC}\n" "$*"; }
log_ok()    { printf "${GREEN}✅ %s${NC}\n" "$*"; }
log_warn()  { printf "${YELLOW}⚠️  %s${NC}\n" "$*"; }
log_err()   { printf "${RED}❌ %s${NC}\n" "$*" >&2; }

# -----------------------------------------------------------------------------
# Docker / Docker Compose detection
# -----------------------------------------------------------------------------

# Detect the available docker compose command.
# Prints "docker compose" or "docker-compose" to stdout.
# Returns non-zero if neither is available (prints nothing).
detect_compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    printf 'docker compose\n'
    return 0
  elif docker-compose version >/dev/null 2>&1; then
    printf 'docker-compose\n'
    return 0
  fi
  return 1
}

# Require docker compose and print it to stdout.
# Exits with an error message if neither is available.
require_compose_cmd() {
  local cmd
  cmd="$(detect_compose_cmd)" || {
    log_err 'docker compose is required but was not found.'
    cat <<'EOF' >&2

Install on macOS:
  brew install docker-compose

Or install Docker Desktop (includes docker compose v2):
  brew install --cask docker

Verify:
  docker compose version
  # or
  docker-compose version
EOF
    exit 1
  }
  printf '%s\n' "${cmd}"
}

# -----------------------------------------------------------------------------
# Shared constants
# -----------------------------------------------------------------------------
TOOLCHAIN_IMAGE="${TOOLCHAIN_IMAGE:-ai-dev:latest}"
NETWORK_NAME="agent-network"
VOLUME_NAME="qdrant_data"

HOST_PROFILE_DIR="${HOME}/.config/ai-harness"
HOST_PROFILE="${HOST_PROFILE_DIR}/host-profile.toml"
PROFILE_VERSION=1

# -----------------------------------------------------------------------------
# TOML parser availability
# -----------------------------------------------------------------------------
if ! python3 -c "
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib
" >/dev/null 2>&1; then
  log_err "Python TOML parser not found."
  cat <<'EOF'

This script requires Python 3.11+ or the 'tomli' package.

Options:
  1. Install Python 3.11+ (recommended):
       brew install python@3.11
  2. Or install tomli for your current Python:
       python3 -m pip install tomli
EOF
  exit 1
fi

# -----------------------------------------------------------------------------
# Utility functions
# -----------------------------------------------------------------------------

# Check if a command exists and optionally check its version.
# Usage: require_cmd "docker" "--version"
require_cmd() {
  local cmd="$1"
  local ver_arg="${2:-}"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    return 1
  fi
  if [[ -n "${ver_arg}" ]]; then
    "${cmd}" "${ver_arg}" 2>/dev/null || echo "unknown"
  fi
  return 0
}

# Read a value from the host profile TOML.
# Usage: read_toml_kv "recommendations.use_china_mirror" "false"
read_toml_kv() {
  local key="$1"
  local default="${2:-}"

  if [[ ! -f "${HOST_PROFILE}" ]]; then
    echo "${default}"
    return
  fi

  # Simple python one-liner to read TOML value
  # Keys like "recommendations.use_china_mirror" are split by dot.
  python3 -c "
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib

try:
    with open('${HOST_PROFILE}', 'rb') as f:
        data = tomllib.load(f)
    keys = '${key}'.split('.')
    val = data
    for k in keys:
        val = val[k]
    if isinstance(val, bool):
        print(str(val).lower())
    else:
        print(val)
except Exception:
    print('${default}')
"
}

# Write a key-value pair to the host profile TOML.
# This is a simplified version that handles basic structure.
# Usage: write_toml_kv "network" "location" "china"
write_toml_kv() {
  local section="$1"
  local key="$2"
  local value="$3"

  mkdir -p "${HOST_PROFILE_DIR}"

  if [[ ! -f "${HOST_PROFILE}" ]]; then
    echo "[meta]" > "${HOST_PROFILE}"
    echo "version = ${PROFILE_VERSION}" >> "${HOST_PROFILE}"
    echo "generated_at = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" >> "${HOST_PROFILE}"
  fi

  # Use python to update/add the value
  # Since tomllib is read-only, we use a simple dict update and manual write for this specific case,
  # or just use a python script that handles the update.
  python3 -c "
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib
import sys, os

profile = '${HOST_PROFILE}'
section = '${section}'
key = '${key}'
value = '${value}'

# Convert to appropriate type
if value.lower() == 'true': value = True
elif value.lower() == 'false': value = False
elif value.isdigit(): value = int(value)

data = {}
if os.path.exists(profile):
    with open(profile, 'rb') as f:
        try:
            data = tomllib.load(f)
        except: pass

if section not in data:
    data[section] = {}
data[section][key] = value

def format_val(v):
    if isinstance(v, bool): return str(v).lower()
    if isinstance(v, int): return str(v)
    return f'\"{v}\"'

with open(profile, 'w') as f:
    for s, kvs in data.items():
        f.write(f'[{s}]\n')
        for k, v in kvs.items():
            f.write(f'{k} = {format_val(v)}\n')
        f.write('\n')
"
}

# Measure latency of a URL using curl.
# Returns latency in milliseconds or -1 on failure.
measure_latency() {
  local url="$1"
  # -w "%{time_total}" returns time in seconds.
  # -m 5 sets timeout to 5 seconds.
  local latency
  latency=$(curl -o /dev/null -s -w "%{time_total}" -m 5 "${url}" || echo "-1")

  if [[ "${latency}" == "-1" ]]; then
    echo "-1"
  else
    # Convert seconds to milliseconds (e.g., 0.123 -> 123)
    echo "${latency} * 1000 / 1" | bc 2>/dev/null || echo "-1"
  fi
}

# Rank mirrors and return the fastest one.
# Usage: rank_mirrors "url1" "url2" "url3"
rank_mirrors() {
  local urls=("$@")
  local best_url=""
  local min_latency=999999

  for url in "${urls[@]}"; do
    local lat
    lat=$(measure_latency "${url}")
    if [[ "${lat}" != "-1" ]] && (( $(echo "${lat} < ${min_latency}" | bc -l) )); then
      min_latency="${lat}"
      best_url="${url}"
    fi
  done

  echo "${best_url}"
}
