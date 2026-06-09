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
TOOLCHAIN_IMAGE="${TOOLCHAIN_IMAGE:-ai-dev-toolchain:latest}"
NETWORK_NAME="agent-network"
VOLUME_NAME="qdrant_data"
