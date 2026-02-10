# OpenClaw Launcher 🐙

[![Build macOS App](https://github.com/Anmol1696/openclaw-launcher/actions/workflows/build-macos.yml/badge.svg)](https://github.com/Anmol1696/openclaw-launcher/actions/workflows/build-macos.yml)
[![Release](https://img.shields.io/github/v/release/Anmol1696/openclaw-launcher?label=release)](https://github.com/Anmol1696/openclaw-launcher/releases/latest)
[![License](https://img.shields.io/github/license/Anmol1696/openclaw-launcher)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-14%2B-blue?logo=apple)](https://github.com/Anmol1696/openclaw-launcher/releases/latest)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)](https://swift.org)

> **Beta** — UI and features are actively evolving.

**Double-click → Docker runs in lockdown → browser opens → done.**

No Terminal. No Node.js. No PATH issues. No CLI.

Native SwiftUI app handles everything silently in the background.

---

## Prerequisites

- [**Docker Desktop**](https://www.docker.com/products/docker-desktop/) — required to run the OpenClaw container

## Quick Start

### Download (macOS)

[**⬇️ Download OpenClawLauncher.dmg**](https://github.com/Anmol1696/openclaw-launcher/releases/latest/download/OpenClawLauncher.dmg)

1. Open the DMG and drag **OpenClawLauncher.app** to `/Applications`
2. Double-click to launch

### Alternative: Homebrew

```bash
brew tap anmol1696/openclaw-launcher
brew install --cask openclaw-launcher
```

### Alternative: One-liner (macOS/Linux)

```bash
curl -fsSL https://raw.githubusercontent.com/Anmol1696/openclaw-launcher/main/scripts/run.sh | bash
```

Requires: Docker, curl, python3, openssl

### Then...

1. **Double-click** OpenClawLauncher.app
2. If Docker Desktop isn't installed, the app will guide you to download it
3. The app pulls the OpenClaw image and launches the container
4. Your browser opens automatically — paste the gateway token, sign in with your AI provider, and start chatting

That's it. Everything persists across restarts in `~/.openclaw-launcher/`.

> **First launch?** The app handles image pulling, token generation, and auth setup. Just follow the on-screen progress bar.

---

## How It Works

```
User double-clicks OpenClawLauncher.app
         │
         ▼
┌──────────────────────────────────────────────────────────┐
│  Native SwiftUI Window                                   │
│                                                          │
│  ┌─ Setup ──────────────────────────────────────────┐    │
│  │  [████████░░░░░░░░] 50%                          │    │
│  │  ⏳ Pulling Docker image...                      │    │
│  │  ✅ 4 steps completed                            │    │
│  └──────────────────────────────────────────────────┘    │
│                                                          │
│  ┌─ Dashboard (after launch) ───────────────────────┐    │
│  │  🟢 Container Status: Running    00:05:23        │    │
│  │  💡 Chat with your agent in the Control UI.      │    │
│  │  [ Open Control UI ]                             │    │
│  │  [ View Logs ] [ Restart ] [ Stop ]              │    │
│  └──────────────────────────────────────────────────┘    │
│                                                          │
│  🐙● Menu bar icon (green/yellow/red status)             │
└──────────────────────────────────────────────────────────┘
         │
         ▼  (browser opens automatically)
┌──────────────────────────────────────────────────────────┐
│  http://localhost:18789 — Control UI (browser)           │
│  ┌────────────────────────────────────────────────────┐  │
│  │  Paste token → Sign in with Anthropic/OpenAI       │  │
│  │  Chat with agent                                   │  │
│  │  Configure channels (WhatsApp, Telegram, etc.)     │  │
│  │  All settings managed here                         │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
         │
         ▼  (inside Docker, user never sees this)
┌──────────────────────────────────────────────────────────┐
│  Docker Container (LOCKDOWN MODE)                        │
│  ├── --read-only           (immutable root filesystem)   │
│  ├── --cap-drop ALL        (zero Linux capabilities)     │
│  ├── --memory 2g           (resource capped)             │
│  ├── --pids-limit 256      (no fork bombs)               │
│  ├── --no-new-privileges   (no escalation)               │
│  ├── -p 127.0.0.1:18789   (localhost only, not LAN)     │
│  ├── non-root user         (node:openclaw)               │
│  └── tini as PID 1         (proper signal handling)      │
└──────────────────────────────────────────────────────────┘
```

## Features

- **Progress bar** during setup with current step and completion count
- **Dashboard** after launch with container status, health indicator, uptime timer
- **Menu bar icon** with green/yellow/red status dot and quick actions
- **Health checks** polling the gateway every 5 seconds
- **Docker guidance** with download link if Docker Desktop is not found
- **OAuth + API key auth** on first run, or skip and configure later in browser

## Shell Commands

If you cloned the repo or used the one-liner:

```bash
./run.sh           # Start (or re-run)
./run.sh stop      # Stop container
./run.sh start     # Start stopped container
./run.sh logs      # Follow container logs
./run.sh status    # Check if running
./run.sh reset     # Delete everything and start fresh
```

---

## Build from Source

Requires Xcode (full install, not just Command Line Tools) for SwiftUI.

```bash
# Build .app + .dmg
cd app/macos && bash build.sh

# Output:
#   dist/OpenClawLauncher.app    ← drag to /Applications
#   dist/OpenClawLauncher.dmg    ← share with others

# Run tests
cd app/macos && swift test
```

Or let CI build it — push to `main` and download the `.dmg` artifact from GitHub Actions.

## Project Structure

```
openclaw-launcher/
├── run.sh                    # Shell launcher (for devs)
├── docker/
│   ├── Dockerfile            # Multi-stage build (targets: base, lite, full)
│   └── README.md             # Flavor docs + build instructions
├── app/macos/
│   ├── Package.swift         # Swift package manifest
│   ├── Sources/
│   │   ├── OpenClawApp/
│   │   │   └── OpenClawApp.swift  # App entry point + MenuBarExtra
│   │   └── OpenClawLib/
│   │       ├── Models.swift           # Data types, enums, errors
│   │       ├── LauncherViews.swift    # SwiftUI views (dashboard, setup, cards)
│   │       ├── OpenClawLauncher.swift # Core logic (Docker, health, timers)
│   │       └── AnthropicOAuth.swift   # OAuth PKCE flow
│   ├── Tests/OpenClawTests/  # Unit tests
│   ├── build.sh              # Compiles Swift → .app → .dmg
│   └── scripts/              # Build helpers (icon generation)
├── docs/plan/                # Planning docs
└── .github/workflows/        # CI (build + test)
```

## Docker Image Flavors

Slim Docker images that install OpenClaw via npm — **70% smaller** than upstream.

| Flavor | Tag | What's included | Image size |
|--------|-----|-----------------|------------|
| **slim** | `slim` | OpenClaw + jq, ripgrep, fd, sqlite3 | ~300 MB |
| **base** | `base` | slim + node-llama-cpp (local LLM) | ~500 MB |
| **full** | `full` | base + Python 3, Playwright, ffmpeg | ~1.2 GB |

**Recommended:** Use `base` for future-proof local LLM support.

```bash
OPENCLAW_FLAVOR=base ./scripts/run.sh
```

See [`docker/README.md`](docker/README.md) for build instructions and full tool inventory.

---

## Security: Lockdown Mode

The Docker container runs with maximum restrictions:

| Security Feature         | Setting                          |
|--------------------------|----------------------------------|
| Root filesystem          | `--read-only`                    |
| Linux capabilities       | `--cap-drop ALL`                 |
| Privilege escalation     | `--no-new-privileges`            |
| Memory limit             | `--memory 2g --memory-swap 2g`   |
| CPU limit                | `--cpus 2.0`                     |
| Process limit            | `--pids-limit 256`               |
| Network exposure         | `127.0.0.1` only (not LAN)      |
| Container user           | Non-root (`node:openclaw`)       |
| PID 1                    | `tini` (proper signal handling)  |
| Temp filesystem          | `noexec,nosuid` tmpfs            |
| Gateway auth             | Token required (auto-generated)  |

The container **cannot**:
- Write to its own filesystem (read-only root)
- Gain new privileges or capabilities
- Exceed memory/CPU/process limits
- Be accessed from other machines on the network
- Run without authentication

## API Key / Auth

OpenClaw is an AI agent — it calls Claude, GPT, Gemini, etc. to think.
It needs credentials for that. The Control UI (in browser) handles this:

- **OAuth sign-in**: Click "Sign in with Anthropic" (uses your Claude Pro/Max sub)
- **API key**: Paste an Anthropic/OpenAI key in the settings panel

Nothing to edit in files or Terminal. All in the browser.

## Troubleshooting

| Problem                  | Fix                                      |
|--------------------------|------------------------------------------|
| "Docker not found"       | Install [Docker Desktop](https://www.docker.com/products/docker-desktop/) |
| App shows spinner        | Docker Desktop might be starting (~30s)  |
| Can't connect to UI      | `docker ps` — ensure port 18789 is free  |
| Lost gateway token       | `cat ~/.openclaw-launcher/.env`          |
| Want to start fresh      | Delete `~/.openclaw-launcher/` folder    |

---

Powered by [Constructive](https://constructive.io)
