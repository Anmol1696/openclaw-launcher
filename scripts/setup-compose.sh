#!/bin/bash
# ============================================================================
#  Setup script for docker-compose
#  Creates the necessary directories and config files
# ============================================================================

set -euo pipefail

STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw-launcher}"
CONFIG_DIR="$STATE_DIR/config"
WORKSPACE_DIR="$STATE_DIR/workspace"
ENV_FILE="$STATE_DIR/.env"
PORT="${OPENCLAW_PORT:-18789}"

echo "🐙 OpenClaw Launcher - Docker Compose Setup"
echo ""

# Create directories
mkdir -p "$CONFIG_DIR/agents/default/agent" "$CONFIG_DIR/agents/default/sessions" "$CONFIG_DIR/credentials"
mkdir -p "$WORKSPACE_DIR"
chmod 700 "$CONFIG_DIR/credentials"

# Generate token if .env doesn't exist
if [ ! -f "$ENV_FILE" ]; then
    TOKEN=$(openssl rand -hex 32)
    cat > "$ENV_FILE" <<EOF
OPENCLAW_GATEWAY_TOKEN=$TOKEN
OPENCLAW_PORT=$PORT
EOF
    chmod 600 "$ENV_FILE"
    echo "✅ Generated gateway token"

    # Create config file
    cat > "$CONFIG_DIR/openclaw.json" <<CONF
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "auth": {
      "mode": "token",
      "token": "$TOKEN"
    },
    "controlUi": {
      "enabled": true,
      "basePath": "/openclaw",
      "dangerouslyDisableDeviceAuth": true
    }
  },
  "agents": {
    "defaults": {
      "workspace": "/home/node/.openclaw/workspace",
      "model": { "primary": "anthropic/claude-opus-4-5" }
    }
  }
}
CONF
    chmod 600 "$CONFIG_DIR/openclaw.json"
    echo "✅ Created config at $CONFIG_DIR/openclaw.json"
else
    echo "✅ Config already exists at $ENV_FILE"
    source "$ENV_FILE"
    TOKEN="$OPENCLAW_GATEWAY_TOKEN"
fi

echo ""
echo "📁 State directory: $STATE_DIR"
echo "🔑 Gateway token:   $TOKEN"
echo "🌐 Port:            $PORT"
echo ""
echo "To start:"
echo "  docker-compose up -d"
echo ""
echo "Control UI will be at:"
echo "  http://localhost:$PORT/openclaw?token=$TOKEN"
echo ""
