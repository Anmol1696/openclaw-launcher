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

## Quick Start

1. **Download** the latest [`OpenClawLauncher.dmg`](https://github.com/Anmol1696/openclaw-launcher/releases/latest)
2. **Open** the DMG and drag **OpenClawLauncher.app** to `/Applications`
3. **Double-click** OpenClawLauncher.app
4. The app will install Docker Desktop for you if needed, pull the OpenClaw image, and launch the container
5. Your browser opens automatically — paste the gateway token, sign in with your AI provider, and start chatting

That's it. Everything persists across restarts in `~/.openclaw-launcher/`.

> **First launch?** The app handles Docker Desktop installation, image pulling, token generation, and auth setup. Just follow the on-screen progress bar.

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
- **Docker auto-install** if Docker Desktop is not found
- **OAuth + API key auth** on first run, or skip and configure later in browser

## Install & Run

### Shell script (for devs)

```bash
# Prerequisites: Docker Desktop running
./run.sh           # Start
./run.sh stop      # Stop
./run.sh logs      # Follow logs
./run.sh status    # Check if running
./run.sh reset     # Nuke and start fresh
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
| "Docker not found"       | Install Docker Desktop (or let the app do it) |
| App shows spinner        | Docker Desktop might be starting (~30s)  |
| Can't connect to UI      | `docker ps` — ensure port 18789 is free  |
| Lost gateway token       | `cat ~/.openclaw-launcher/.env`          |
| Want to start fresh      | Delete `~/.openclaw-launcher/` folder    |
