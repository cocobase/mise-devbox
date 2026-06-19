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
# Optional Python availability
# -----------------------------------------------------------------------------
if ! command -v python3 >/dev/null 2>&1; then
  log_warn "python3 not found; continuing because host profile TOML handling is pure Bash/awk."
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
  local dotted_key="$1"
  local default="${2:-}"
  local section="${dotted_key%.*}"
  local key="${dotted_key##*.}"

  if [[ ! -f "${HOST_PROFILE}" ]]; then
    echo "${default}"
    return
  fi

  awk -v target_section="${section}" -v target_key="${key}" -v default_value="${default}" '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }
    function strip_inline_comment(s,    i, c, prev, quote, out) {
      quote = ""
      out = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        prev = (i > 1) ? substr(s, i - 1, 1) : ""
        if ((c == "\"" || c == "'\''") && prev != "\\") {
          if (quote == "") quote = c
          else if (quote == c) quote = ""
        }
        if (c == "#" && quote == "") break
        out = out c
      }
      return trim(out)
    }
    function normalize_value(s, lower) {
      s = strip_inline_comment(s)
      if ((substr(s, 1, 1) == "\"" && substr(s, length(s), 1) == "\"") ||
          (substr(s, 1, 1) == "'\''" && substr(s, length(s), 1) == "'\''")) {
        s = substr(s, 2, length(s) - 2)
      }
      lower = tolower(s)
      if (lower == "true" || lower == "false") return lower
      return s
    }
    BEGIN {
      current_section = ""
      found = 0
    }
    /^[[:space:]]*\[[^][]+\][[:space:]]*([#].*)?$/ {
      line = $0
      sub(/^[[:space:]]*\[/, "", line)
      sub(/\][[:space:]]*([#].*)?$/, "", line)
      current_section = trim(line)
      next
    }
    current_section == target_section {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (line ~ ("^" target_key "[[:space:]]*=")) {
        sub(("^" target_key "[[:space:]]*=[[:space:]]*"), "", line)
        print normalize_value(line)
        found = 1
        exit
      }
    }
    END {
      if (!found) print default_value
    }
  ' "${HOST_PROFILE}"
}

# Write a key-value pair to the host profile TOML.
# Usage: write_toml_kv "network" "location" "china"
write_toml_kv() {
  local section="$1"
  local key="$2"
  local value="$3"
  local formatted_value
  local tmp_file

  mkdir -p "${HOST_PROFILE_DIR}"

  if [[ ! -f "${HOST_PROFILE}" ]]; then
    {
      printf '[meta]\n'
      printf 'version = %s\n' "${PROFILE_VERSION}"
      printf 'generated_at = "%s"\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "${HOST_PROFILE}"
  fi

  case "${value}" in
    [Tt][Rr][Uu][Ee]) formatted_value="true" ;;
    [Ff][Aa][Ll][Ss][Ee]) formatted_value="false" ;;
    ''|*[!0-9]*)
      value="${value//\\/\\\\}"
      value="${value//\"/\\\"}"
      formatted_value="\"${value}\""
      ;;
    *) formatted_value="${value}" ;;
  esac

  tmp_file="$(mktemp "${HOST_PROFILE}.tmp.XXXXXX")"
  awk -v target_section="${section}" -v target_key="${key}" -v target_value="${formatted_value}" '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }
    function print_pending_key() {
      if (in_target && !key_written) {
        print target_key " = " target_value
        key_written = 1
      }
    }
    BEGIN {
      current_section = ""
      in_target = 0
      section_found = 0
      key_written = 0
    }
    /^[[:space:]]*\[[^][]+\][[:space:]]*([#].*)?$/ {
      print_pending_key()
      line = $0
      sub(/^[[:space:]]*\[/, "", line)
      sub(/\][[:space:]]*([#].*)?$/, "", line)
      current_section = trim(line)
      in_target = (current_section == target_section)
      if (in_target) section_found = 1
      print
      next
    }
    in_target {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (line ~ ("^" target_key "[[:space:]]*=")) {
        print target_key " = " target_value
        key_written = 1
        next
      }
    }
    { print }
    END {
      print_pending_key()
      if (!section_found) {
        if (NR > 0) print ""
        print "[" target_section "]"
        print target_key " = " target_value
      }
    }
  ' "${HOST_PROFILE}" > "${tmp_file}"
  mv "${tmp_file}" "${HOST_PROFILE}"
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
