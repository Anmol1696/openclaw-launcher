#!/bin/bash
# ============================================================================
#  OpenClaw Launcher — double-click to run
#  Runs OpenClaw Gateway in an isolated Docker container.
#  Control UI opens in your browser at http://localhost:18789
# ============================================================================

set -euo pipefail

# --- Config ---
CONTAINER_NAME="openclaw"
IMAGE_NAME="ghcr.io/openclaw/openclaw:latest"
STATE_DIR="$HOME/.openclaw-launcher"
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
#  Step 1a: Install Docker Desktop (macOS only)
# ============================================================================
install_docker() {
    log "Docker Desktop not found. Downloading..."

    local arch
    arch=$(uname -m)
    local dmg_url
    if [ "$arch" = "arm64" ]; then
        dmg_url="https://desktop.docker.com/mac/main/arm64/Docker.dmg"
    else
        dmg_url="https://desktop.docker.com/mac/main/amd64/Docker.dmg"
    fi

    local dmg_path="/tmp/Docker.dmg"
    rm -f "$dmg_path"

    log "Downloading Docker Desktop ($arch)... This may take a few minutes."
    curl -L -o "$dmg_path" "$dmg_url" || fail "Download failed."

    ok "Download complete."
    log "Installing Docker Desktop..."

    hdiutil attach -nobrowse -quiet "$dmg_path" || fail "Failed to mount DMG."

    if [ ! -d "/Volumes/Docker/Docker.app" ]; then
        hdiutil detach "/Volumes/Docker" -quiet 2>/dev/null
        fail "Docker.app not found in mounted DMG."
    fi

    if cp -R "/Volumes/Docker/Docker.app" "/Applications/Docker.app" 2>/dev/null; then
        ok "Docker Desktop installed."
    else
        warn "Requesting administrator permission to install..."
        sudo cp -R "/Volumes/Docker/Docker.app" "/Applications/Docker.app" || {
            hdiutil detach "/Volumes/Docker" -quiet 2>/dev/null
            fail "Installation failed."
        }
        ok "Docker Desktop installed."
    fi

    hdiutil detach "/Volumes/Docker" -quiet 2>/dev/null
    rm -f "$dmg_path"
}

# ============================================================================
#  Step 1b: Check Docker
# ============================================================================
check_docker() {
    if ! command -v docker &>/dev/null && [ ! -d "/Applications/Docker.app" ]; then
        if [ "$(uname)" = "Darwin" ]; then
            install_docker
        else
            fail "Docker not found. Install Docker first: https://docs.docker.com/engine/install/"
        fi
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
#  OAuth: Sign in with Claude (PKCE flow)
# ============================================================================
OAUTH_CLIENT_ID="9d1c250a-e61b-44d9-88ed-5944d1962f5e"
OAUTH_AUTHORIZE_URL="https://claude.ai/oauth/authorize"
OAUTH_TOKEN_URL="https://console.anthropic.com/v1/oauth/token"
OAUTH_REDIRECT_URI="https://console.anthropic.com/oauth/code/callback"
OAUTH_SCOPES="org:create_api_key user:profile user:inference"

base64url_encode() {
    openssl base64 -A | tr '+/' '-_' | tr -d '='
}

oauth_sign_in() {
    log "Starting OAuth sign-in..."

    # Generate PKCE verifier + challenge
    local verifier challenge
    verifier=$(openssl rand 32 | base64url_encode)
    challenge=$(printf '%s' "$verifier" | openssl dgst -sha256 -binary | base64url_encode)

    # Build authorize URL
    local auth_url="${OAUTH_AUTHORIZE_URL}?code=true"
    auth_url+="&client_id=${OAUTH_CLIENT_ID}"
    auth_url+="&response_type=code"
    auth_url+="&redirect_uri=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${OAUTH_REDIRECT_URI}'))")"
    auth_url+="&scope=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${OAUTH_SCOPES}'))")"
    auth_url+="&code_challenge=${challenge}"
    auth_url+="&code_challenge_method=S256"
    auth_url+="&state=${verifier}"

    # Open browser
    log "Opening browser for sign-in..."
    if [ "$(uname)" = "Darwin" ]; then
        open "$auth_url"
    elif command -v xdg-open &>/dev/null; then
        xdg-open "$auth_url"
    else
        echo "   Open this URL in your browser:"
        echo "   $auth_url"
    fi

    echo ""
    echo "   After signing in, you'll see a page with an authorization code."
    echo "   Copy the code (or the full URL) and paste it below."
    echo ""
    read -rp "   Authorization code: " raw_code

    # Extract code from URL if user pasted a full URL
    local code="$raw_code"
    if [[ "$raw_code" == http* ]]; then
        code=$(python3 -c "from urllib.parse import urlparse, parse_qs; print(parse_qs(urlparse('${raw_code}').query).get('code',[''])[0])")
    fi

    # Handle code#state format from Anthropic callback
    if [[ "$code" == *"#"* ]]; then
        code="${code%%#*}"
    fi

    if [ -z "$code" ]; then
        warn "No code provided — skipping OAuth."
        return
    fi

    # Exchange code for tokens
    log "Exchanging authorization code..."
    local response
    response=$(curl -s -X POST "$OAUTH_TOKEN_URL" \
        -H "Content-Type: application/json" \
        -d "{
            \"grant_type\": \"authorization_code\",
            \"client_id\": \"${OAUTH_CLIENT_ID}\",
            \"code\": \"${code}\",
            \"state\": \"${verifier}\",
            \"redirect_uri\": \"${OAUTH_REDIRECT_URI}\",
            \"code_verifier\": \"${verifier}\"
        }")

    # Parse response
    local access_token refresh_token expires_in
    access_token=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)
    refresh_token=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('refresh_token',''))" 2>/dev/null)
    expires_in=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('expires_in',0))" 2>/dev/null)

    if [ -z "$access_token" ] || [ -z "$refresh_token" ]; then
        warn "OAuth exchange failed. Server response:"
        echo "   $response"
        return
    fi

    # Calculate expires_at (ms) — now + expires_in - 5 min buffer
    local now_ms expires_at_ms
    now_ms=$(python3 -c "import time; print(int(time.time()*1000))")
    expires_at_ms=$(python3 -c "print(${now_ms} + int(${expires_in})*1000 - 5*60*1000)")

    # Write credentials
    mkdir -p "$CONFIG_DIR/credentials"
    chmod 700 "$CONFIG_DIR/credentials"
    cat > "$CONFIG_DIR/credentials/oauth.json" <<OAUTHEOF
{
  "anthropic": {
    "type": "oauth",
    "refresh": "$refresh_token",
    "access": "$access_token",
    "expires": $expires_at_ms
  }
}
OAUTHEOF
    chmod 600 "$CONFIG_DIR/credentials/oauth.json"

    ok "Signed in with Claude"
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
    chmod 600 "$ENV_FILE"

    # Write config with actual token value (not env var reference)
    cat > "$CONFIG_DIR/openclaw.json" <<CONF
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "auth": {
      "mode": "token",
      "token": "$token"
    },
    "controlUi": {
      "enabled": true,
      "basePath": "/openclaw"
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

    # Create agent directories
    mkdir -p "$CONFIG_DIR/agents/default/agent" "$CONFIG_DIR/agents/default/sessions"

    ok "Config created at $STATE_DIR"
    echo ""
    echo -e "   ${CYAN}Gateway token:${NC} $token"
    echo -e "   ${CYAN}Config dir:${NC}    $CONFIG_DIR"
    echo ""

    # Auth setup menu
    echo -e "   ${CYAN}Authentication${NC}"
    echo "   Choose how to connect to Anthropic:"
    echo ""
    echo "   1) Sign in with Claude (OAuth — recommended for Pro/Max)"
    echo "   2) Use API Key"
    echo "   3) Skip (set up later in browser)"
    echo ""
    read -rp "   Choice [1/2/3]: " auth_choice

    case "${auth_choice}" in
        1)
            oauth_sign_in
            ;;
        2)
            read -rp "   Anthropic API key (sk-ant-...): " api_key
            if [ -n "$api_key" ]; then
                cat > "$CONFIG_DIR/agents/default/agent/auth-profiles.json" <<AUTHEOF
{
  "version": 1,
  "profiles": {
    "anthropic:default": {
      "type": "api_key",
      "provider": "anthropic",
      "key": "$api_key"
    }
  }
}
AUTHEOF
                chmod 600 "$CONFIG_DIR/agents/default/agent/auth-profiles.json"
                ok "API key saved"
            else
                warn "Empty key — skipped."
            fi
            ;;
        *)
            warn "Skipped — set up authentication in the Control UI settings."
            ;;
    esac
    echo ""
}

# ============================================================================
#  Step 3: Build image (if needed)
# ============================================================================
pull_image() {
    if docker image inspect "$IMAGE_NAME" &>/dev/null 2>&1; then
        return 0
    fi

    log "Pulling OpenClawLauncher Docker image..."
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
            ok "OpenClawLauncher is already running."
            open_browser
            return 0
        fi

        # Container exists but stopped — remove and recreate
        log "Removing stopped container..."
        docker rm "$CONTAINER_NAME" &>/dev/null || true
    fi

    log "Starting OpenClawLauncher..."

    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        --init \
        -p "${OPENCLAW_PORT}:18789" \
        -v "${CONFIG_DIR}:/home/node/.openclaw" \
        -v "${WORKSPACE_DIR}:/home/node/.openclaw/workspace" \
        -e "HOME=/home/node" \
        -e "TERM=xterm-256color" \
        --env-file "$ENV_FILE" \
        "$IMAGE_NAME" \
        node dist/index.js gateway --bind lan --port 18789 \
        > /dev/null

    # Wait for Gateway to be ready
    log "Waiting for Gateway..."
    for i in $(seq 1 30); do
        if curl -sf "http://localhost:${OPENCLAW_PORT}/openclaw/" > /dev/null 2>&1; then
            echo ""
            ok "OpenClawLauncher is running!"
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
    local url="http://localhost:${OPENCLAW_PORT}/openclaw?token=${OPENCLAW_GATEWAY_TOKEN}"

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
    echo "  ║       🐙  OpenClawLauncher           ║"
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
