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
│  ☑ Building Docker image...    ✅  (first launch only)   │
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

## User Journey

1. **Install Docker Desktop** (one-time prerequisite)
2. **Double-click OpenClaw.app**
3. Small native window shows progress (no Terminal)
4. Browser opens → paste token → sign in with your AI provider
5. Start chatting

That's it. Everything persists across restarts in `~/.openclaw-docker/`.

---

## Files

```
openclaw-launcher/
├── Sources/main.swift    # Native SwiftUI macOS app (no Terminal)
├── Package.swift         # Swift package manifest
├── Dockerfile            # Hardened multi-stage Docker image
├── openclaw.sh           # Shell script alternative (for devs)
├── build-app.sh          # Compiles Swift → .app → .dmg
└── README.md
```

## Build

```bash
# Prerequisites: Xcode command line tools
xcode-select --install

# Build the .app + .dmg
chmod +x build-app.sh
./build-app.sh

# Output:
#   dist/OpenClaw.app    ← drag to /Applications
#   dist/OpenClaw.dmg    ← share with others
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

## Shell Script Alternative (for devs)

```bash
./openclaw.sh           # Start
./openclaw.sh stop      # Stop
./openclaw.sh logs      # Follow logs
./openclaw.sh status    # Check if running
./openclaw.sh reset     # Nuke and start fresh
```

## Troubleshooting

| Problem                  | Fix                                      |
|--------------------------|------------------------------------------|
| "Docker not found"       | Install Docker Desktop                   |
| App shows spinner        | Docker Desktop might be starting (~30s)  |
| Can't connect to UI      | `docker ps` — ensure port 18789 is free  |
| Lost gateway token       | `cat ~/.openclaw-docker/.env`            |
| Want to start fresh      | Delete `~/.openclaw-docker/` folder      |
