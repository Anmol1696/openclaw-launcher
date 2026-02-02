#!/bin/bash
# ============================================================================
#  OpenClaw Launcher — double-click to run
#  Runs OpenClaw Gateway in an isolated Docker container.
#  Control UI opens in your browser at http://localhost:18789
# ============================================================================

set -euo pipefail

# --- Config ---
CONTAINER_NAME="openclaw"
IMAGE_NAME="ghcr.io/anmol1696/openclaw:latest"
STATE_DIR="$HOME/.openclaw-docker"
CONFIG_DIR="$STATE_DIR/config"
WORKSPACE_DIR="$STATE_DIR/workspace"
PORT="${OPENCLAW_PORT:-18789}"
ENV_FILE="$STATE_DIR/.env"
LOG_FILE="$STATE_DIR/launcher.log"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}🐙${NC} $*"; }
ok()   { echo -e "${GREEN}✅${NC} $*"; }
warn() { echo -e "${YELLOW}⚠️${NC}  $*"; }
fail() { echo -e "${RED}❌${NC} $*"; exit 1; }

# ============================================================================
#  Step 1: Check Docker
# ============================================================================
check_docker() {
    if ! command -v docker &>/dev/null; then
        fail "Docker not found. Install Docker Desktop first."
        echo "   https://docker.com/products/docker-desktop"
        [ "$(uname)" = "Darwin" ] && open "https://docker.com/products/docker-desktop"
        exit 1
    fi

    if ! docker info &>/dev/null 2>&1; then
        warn "Docker is installed but not running. Starting Docker Desktop..."
        if [ "$(uname)" = "Darwin" ]; then
            open -a "Docker"
            log "Waiting for Docker to start (this can take 30-60 seconds)..."
            for i in $(seq 1 60); do
                if docker info &>/dev/null 2>&1; then
                    ok "Docker is ready."
                    return 0
                fi
                sleep 2
                printf "."
            done
            echo ""
            fail "Docker didn't start in time. Please start Docker Desktop manually."
        else
            fail "Please start Docker and try again."
        fi
    fi
}

# ============================================================================
#  Step 2: First-run setup (generate token, create config)
# ============================================================================
first_run_setup() {
    if [ -f "$ENV_FILE" ]; then
        return 0
    fi

    log "First-time setup..."
    mkdir -p "$CONFIG_DIR" "$WORKSPACE_DIR"

    # Generate secure gateway token
    local token
    if command -v openssl &>/dev/null; then
        token=$(openssl rand -hex 32)
    else
        token=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    fi

    # Save env
    cat > "$ENV_FILE" <<EOF
OPENCLAW_GATEWAY_TOKEN=$token
OPENCLAW_PORT=$PORT
EOF

    # Write minimal config that lets Gateway start headless
    # The Control UI handles everything else (API keys, channels, etc.)
    cat > "$CONFIG_DIR/openclaw.json" <<CONF
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "auth": {
      "mode": "token"
    },
    "controlUi": {
      "enabled": true,
      "allowInsecureAuth": true
    },
    "http": {
      "endpoints": {
        "chatCompletions": { "enabled": true }
      }
    }
  },
  "agents": {
    "defaults": {
      "workspace": "/home/node/.openclaw/workspace"
    }
  }
}
CONF

    ok "Config created at $STATE_DIR"
    echo ""
    echo -e "   ${CYAN}Gateway token:${NC} $token"
    echo -e "   ${CYAN}Config dir:${NC}    $CONFIG_DIR"
    echo -e "   ${CYAN}Workspace:${NC}     $WORKSPACE_DIR"
    echo ""
    echo "   You'll set up your API key in the browser after launch."
    echo ""
}

# ============================================================================
#  Step 3: Build image (if needed)
# ============================================================================
pull_image() {
    if docker image inspect "$IMAGE_NAME" &>/dev/null 2>&1; then
        return 0
    fi

    log "Pulling OpenClaw Docker image..."
    docker pull "$IMAGE_NAME" 2>&1 | tee "$LOG_FILE"
    ok "Image pulled."
}

# ============================================================================
#  Step 4: Run container
# ============================================================================
run_container() {
    # Load saved env
    source "$ENV_FILE"

    # Stop existing container if running
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        local state
        state=$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "none")

        if [ "$state" = "running" ]; then
            ok "OpenClaw is already running."
            open_browser
            return 0
        fi

        # Container exists but stopped — remove and recreate
        log "Removing stopped container..."
        docker rm "$CONTAINER_NAME" &>/dev/null || true
    fi

    log "Starting OpenClaw..."

    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        --init \
        -p "${OPENCLAW_PORT}:18789" \
        -v "${CONFIG_DIR}:/home/node/.openclaw" \
        -v "${WORKSPACE_DIR}:/home/node/.openclaw/workspace" \
        -e "HOME=/home/node" \
        -e "TERM=xterm-256color" \
        -e "OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}" \
        "$IMAGE_NAME" \
        node dist/index.mjs gateway --bind lan --port 18789 \
        > /dev/null

    # Wait for Gateway to be ready
    log "Waiting for Gateway..."
    for i in $(seq 1 30); do
        if curl -sf "http://localhost:${OPENCLAW_PORT}/" > /dev/null 2>&1; then
            echo ""
            ok "OpenClaw is running!"
            open_browser
            return 0
        fi
        sleep 1
        printf "."
    done

    echo ""
    warn "Gateway is slow to start. Check logs:"
    echo "   docker logs $CONTAINER_NAME"
}

# ============================================================================
#  Step 5: Open browser
# ============================================================================
open_browser() {
    source "$ENV_FILE"
    local url="http://localhost:${OPENCLAW_PORT}"

    echo ""
    echo -e "   ${CYAN}Control UI:${NC}  $url"
    echo -e "   ${CYAN}Token:${NC}       ${OPENCLAW_GATEWAY_TOKEN}"
    echo ""
    echo "   Paste the token when the Control UI asks for authentication."
    echo ""

    if [ "$(uname)" = "Darwin" ]; then
        open "$url"
    elif command -v xdg-open &>/dev/null; then
        xdg-open "$url"
    fi
}

# ============================================================================
#  Main
# ============================================================================
main() {
    echo ""
    echo "  ╔═══════════════════════════════════════╗"
    echo "  ║         🐙  OpenClaw Launcher         ║"
    echo "  ╠═══════════════════════════════════════╣"
    echo "  ║  Isolated Docker · Browser Control UI ║"
    echo "  ╚═══════════════════════════════════════╝"
    echo ""

    check_docker
    first_run_setup
    pull_image
    run_container

    echo ""
    echo "  ─────────────────────────────────────────"
    echo "  Commands:"
    echo "    Stop:    docker stop $CONTAINER_NAME"
    echo "    Start:   docker start $CONTAINER_NAME"
    echo "    Logs:    docker logs -f $CONTAINER_NAME"
    echo "    Reset:   docker rm -f $CONTAINER_NAME && rm -rf $STATE_DIR"
    echo "  ─────────────────────────────────────────"
    echo ""
}

# Handle arguments
case "${1:-}" in
    stop)
        docker stop "$CONTAINER_NAME" 2>/dev/null && ok "Stopped." || warn "Not running."
        ;;
    start)
        docker start "$CONTAINER_NAME" 2>/dev/null && ok "Started." && open_browser || warn "Container not found. Run without arguments first."
        ;;
    logs)
        docker logs -f "$CONTAINER_NAME"
        ;;
    status)
        if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            ok "Running on http://localhost:${PORT}"
        else
            warn "Not running."
        fi
        ;;
    reset)
        docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
        rm -rf "$STATE_DIR"
        ok "Reset complete. Run again to set up fresh."
        ;;
    *)
        main
        ;;
esac

