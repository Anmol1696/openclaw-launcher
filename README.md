# OpenClaw Launcher 🐙

**Double-click → Docker runs in lockdown → browser opens → done.**

No Terminal. No Node.js. No PATH issues. No CLI.

Native SwiftUI app handles everything silently in the background.

---

## How It Works

```
User double-clicks OpenClaw.app
         │
         ▼
┌──────────────────────────────────────────────────────────┐
│  Native SwiftUI Window (no Terminal)                     │
│  ☑ Checking Docker...          ✅                        │
│  ☑ First-time setup...         ✅                        │
│  ☑ Pulling Docker image...     ✅  (checks for updates)   │
│  ☑ Starting container...       ✅  (lockdown mode)       │
│  ☑ Waiting for Gateway...      ✅                        │
│                                                          │
│  Token: a8f3b2c1...    [Copy]                            │
│  [ Open Control UI ]   [ Stop ]                          │
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

## Install & Run

### macOS App (recommended)

1. **Install [Docker Desktop](https://docker.com/products/docker-desktop)** (one-time)
2. **Download `OpenClaw.dmg`** from the [latest release](https://github.com/Anmol1696/openclaw-launcher/releases/latest)
3. Open the DMG, drag **OpenClaw.app** to `/Applications`
4. Double-click **OpenClaw.app**
5. Browser opens → paste token → sign in with your AI provider → start chatting

Everything persists across restarts in `~/.openclaw-docker/`.

### Shell script (for devs)

```bash
# Prerequisites: Docker Desktop running
./openclaw.sh           # Start
./openclaw.sh stop      # Stop
./openclaw.sh logs      # Follow logs
./openclaw.sh status    # Check if running
./openclaw.sh reset     # Nuke and start fresh
```

---

## Build from Source

Requires Xcode (full install, not just Command Line Tools) for SwiftUI.

```bash
# Build .app + .dmg
cd app/macos && bash build.sh

# Output:
#   dist/OpenClaw.app    ← drag to /Applications
#   dist/OpenClaw.dmg    ← share with others
```

Or let CI build it — push to `main` and download the `.dmg` artifact from GitHub Actions.

## Project Structure

```
openclaw-launcher/
├── Dockerfile                # Hardened Docker image (pushed to ghcr.io)
├── openclaw.sh               # Shell launcher (for devs)
├── app/macos/
│   ├── Package.swift         # Swift package manifest
│   ├── Sources/main.swift    # Native SwiftUI app
│   ├── build.sh              # Compiles Swift → .app → .dmg
│   └── scripts/              # Build helpers (icon generation)
└── .github/workflows/        # CI (Docker publish + macOS build)
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
| "Docker not found"       | Install Docker Desktop                   |
| App shows spinner        | Docker Desktop might be starting (~30s)  |
| Can't connect to UI      | `docker ps` — ensure port 18789 is free  |
| Lost gateway token       | `cat ~/.openclaw-docker/.env`            |
| Want to start fresh      | Delete `~/.openclaw-docker/` folder      |
