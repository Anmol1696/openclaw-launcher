# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

OpenClaw Desktop is a native macOS launcher for the OpenClaw AI Gateway. Users double-click the app, it pulls the upstream Docker image (`ghcr.io/openclaw/openclaw:latest`), runs it in lockdown mode, and opens the Control UI in the browser. No terminal interaction required.

## Repository Structure

```
openclaw.sh             # Shell-based launcher alternative for developers
app/macos/              # Native SwiftUI macOS app
  Package.swift         # Swift package (macOS 14+, Swift 5.9)
  Sources/main.swift    # Single-file SwiftUI app (~500 lines)
  build.sh              # Compiles Swift → .app bundle → .dmg
  scripts/              # Build helpers (icon generation)
dist/                   # Build output (.app, .dmg)
```

## Build Commands

```bash
# Build the macOS .app and .dmg
cd app/macos && bash build.sh
# Output: dist/OpenClawLauncher.app, dist/OpenClawLauncher.dmg (at repo root)

# Swift build only (no .app bundle)
cd app/macos && swift build -c release
```

## Architecture

**main.swift** is a single-file SwiftUI app with this structure:
- `OpenClawApp` — `@main` entry, creates a fixed 480x520 window
- `LauncherView` — main UI with header, scrollable status steps, context-sensitive bottom actions
- `StepRow` — individual status step display (pending/running/done/error/warning)
- `OpenClawLauncher` — `@MainActor ObservableObject` viewmodel that orchestrates the startup sequence:
  1. `checkDocker()` — validates Docker; auto-starts Docker Desktop on macOS (90s timeout)
  2. `firstRunSetup()` — generates 64-char hex token via `SecRandomCopyBytes`, creates `~/.openclaw-docker/` with `.env` and `openclaw.json`
  3. `ensureImage()` — `docker pull ghcr.io/openclaw/openclaw:latest`
  4. `runContainer()` — launches container with comprehensive security flags (read-only FS, cap-drop ALL, memory/CPU/pid limits, localhost-only binding)
  5. `waitForGateway()` — polls `localhost:18789` (30 attempts, 1s apart)

**Docker image**: Uses upstream `ghcr.io/openclaw/openclaw:latest` (multi-arch). The launcher applies lockdown security flags at `docker run` time.

**User data** persists in `~/.openclaw-docker/` with subdirs `config/` and `workspace/`, mounted into the container.

## Key Design Decisions

- Uses the upstream Docker image (`ghcr.io/openclaw/openclaw:latest`) — no custom Dockerfile needed
- The Swift app uses `Process` + `withCheckedThrowingContinuation` for async shell execution
- Container runs in lockdown mode: `--read-only`, `--cap-drop ALL`, `--no-new-privileges`, `--memory 2g`, `--pids-limit 256`, localhost-only port binding
- Gateway token is auto-generated on first run and stored in `~/.openclaw-docker/.env`
