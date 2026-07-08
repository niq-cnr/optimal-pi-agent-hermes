#!/bin/bash
# =============================================================================
# Optimal Pi Agent Launch Script for Hermes Delegation
# =============================================================================
# Usage: ./configs/pi-launch.sh [environment]
#   environment: dev | staging | production (default: dev)
# =============================================================================
# Model stack aligned with opencode-config:
#   github.com/niq-cnr/opencode-config
# =============================================================================

set -euo pipefail

ENVIRONMENT="${1:-dev}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ---------------------------------------------------------------------------
# Model selection per environment — aligned with opencode-config
# ---------------------------------------------------------------------------
# Orchestration/Planning:  zai-coding-plan/glm-5.2
# Implementation/QA:       kimi-for-coding/k2p7 (via Kimi CLI for Agent Swarm)
# Lightweight tasks:       zai-coding-plan/glm-5-turbo
# ---------------------------------------------------------------------------
case "$ENVIRONMENT" in
  dev)
    # Dev: fast, cheap model for rapid iteration
    PI_MODEL="zai-coding-plan/glm-5-turbo"
    MAX_TURNS=30
    SANDBOX_RESOURCES="small"
    LOG_LEVEL="debug"
    ;;
  staging)
    # Staging: GLM-5.2 for validation and testing
    PI_MODEL="zai-coding-plan/glm-5.2"
    MAX_TURNS=50
    SANDBOX_RESOURCES="medium"
    LOG_LEVEL="info"
    ;;
  production)
    # Production: Kimi K2.7 for implementation with Agent Swarm
    # NOTE: This requires Kimi Code CLI subprocess routing (Section 11)
    # The model identifier is resolved by the Kimi CLI, not Pi's direct router
    PI_MODEL="kimi-for-coding/k2p7"
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

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
echo "[pi-launch] Starting Pi Agent for Hermes delegation"
echo "[pi-launch] Environment: $ENVIRONMENT"
echo "[pi-launch] Model: $PI_MODEL"

# Check Z.ai API key is configured
if [ -z "${Z_AI_API_KEY:-}" ]; then
    echo "[pi-launch] WARNING: Z_AI_API_KEY not set in environment"
    echo "[pi-launch] Set it with: export Z_AI_API_KEY='your-key'"
fi

# Check Docker is available
if ! command -v docker &> /dev/null; then
    echo "[pi-launch] ERROR: Docker not found. Container sandbox required."
    exit 1
fi

# Check Pi is installed
if ! command -v pi &> /dev/null; then
    echo "[pi-launch] ERROR: Pi not found. Install with: npm install -g @pi/cli"
    exit 1
fi

# Verify container sandbox extension
if ! pi ext list | grep -q "pi-container-sandbox"; then
    echo "[pi-launch] Installing pi-container-sandbox..."
    pi ext install pi-container-sandbox
fi

# Verify pi-subagents extension
if ! pi ext list | grep -q "pi-subagents"; then
    echo "[pi-launch] Installing pi-subagents..."
    pi ext install pi-subagents
fi

# For production (Kimi K2.7): verify Kimi Code CLI is available
if [ "$ENVIRONMENT" = "production" ] && ! command -v kimi &> /dev/null; then
    echo "[pi-launch] WARNING: Kimi Code CLI not found."
    echo "[pi-launch] Agent Swarm requires: npm install -g @moonshot/kimi-code"
    echo "[pi-launch] Falling back to direct Z.ai API (no Agent Swarm)."
fi

# Create sessions directory
mkdir -p "$HOME/.hermes/pi-sessions"

# ---------------------------------------------------------------------------
# Launch Pi in RPC mode with container sandbox
# ---------------------------------------------------------------------------
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

# Note: For production (kimi-for-coding/k2p7), Pi must route through
# Kimi Code CLI subprocess to access Agent Swarm. See README Section 11.