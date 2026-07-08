#!/bin/bash
# =============================================================================
# Optimal Pi Agent Launch Script for Hermes Delegation
# =============================================================================
# Usage: ./configs/pi-launch.sh [environment]
#   environment: dev | staging | production (default: dev)
# =============================================================================

set -euo pipefail

ENVIRONMENT="${1:-dev}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

case "$ENVIRONMENT" in
  dev)
    PI_MODEL="ollama:codellama:13b"
    MAX_TURNS=30
    SANDBOX_RESOURCES="small"
    LOG_LEVEL="debug"
    ;;
  staging)
    PI_MODEL="openai:gpt-4.1-mini"
    MAX_TURNS=50
    SANDBOX_RESOURCES="medium"
    LOG_LEVEL="info"
    ;;
  production)
    PI_MODEL="claude:claude-sonnet-4.5"
    MAX_TURNS=50
    SANDBOX_RESOURCES="large"
    LOG_LEVEL="warn"
    ;;
  *)
    echo "Unknown environment: $ENVIRONMENT"
    echo "Usage: $0 [dev|staging|production]"
    exit 1
    ;;
esac

echo "[pi-launch] Starting Pi Agent for Hermes delegation"
echo "[pi-launch] Environment: $ENVIRONMENT"
echo "[pi-launch] Model: $PI_MODEL"

if ! command -v docker &> /dev/null; then
    echo "[pi-launch] ERROR: Docker not found. Container sandbox required."
    exit 1
fi

if ! command -v pi &> /dev/null; then
    echo "[pi-launch] ERROR: Pi not found. Install with: npm install -g @pi/cli"
    exit 1
fi

if ! pi ext list | grep -q "pi-container-sandbox"; then
    echo "[pi-launch] Installing pi-container-sandbox..."
    pi ext install pi-container-sandbox
fi

if ! pi ext list | grep -q "pi-subagents"; then
    echo "[pi-launch] Installing pi-subagents..."
    pi ext install pi-subagents
fi

mkdir -p "$HOME/.hermes/pi-sessions"

echo "[pi-launch] Launching Pi Agent..."

exec pi \
  --mode rpc \
  --model "$PI_MODEL" \
  --ext pi-container-sandbox \
  --ext pi-subagents \
  --sandbox-type docker \
  --workspace-mount "$PROJECT_ROOT:/workspace" \
  --sandbox-resources "$SANDBOX_RESOURCES" \
  --max-turns "$MAX_TURNS" \
  --log-level "$LOG_LEVEL" \
  --session-dir "$HOME/.hermes/pi-sessions" \
  "$@"