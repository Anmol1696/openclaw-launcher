# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

OpenClaw Desktop is a native macOS launcher for the OpenClaw AI Gateway. Users double-click the app, it pulls the upstream Docker image (`ghcr.io/openclaw/openclaw:latest`), runs it in lockdown mode, and opens the Control UI in the browser. No terminal interaction required.

## Repository Structure

```
run.sh                  # Shell-based launcher alternative for developers
app/macos/              # Native SwiftUI macOS app
  Package.swift         # Swift package (macOS 14+, Swift 5.9)
  Sources/
    OpenClawApp/
      main.swift        # @main entry point, WindowGroup, MenuBarExtra
    OpenClawLib/
      Models.swift           # StepStatus, LauncherState, MenuBarStatus, GatewayStatus, LaunchStep, ShellResult, LauncherError
      LauncherViews.swift    # LauncherView, DashboardView, SetupView, StatusCard, MenuBarContent, StepRow, auth views
      OpenClawLauncher.swift # @MainActor ObservableObject — Docker lifecycle, health checks, timers
      AnthropicOAuth.swift   # OAuth PKCE flow, OAuthCredentials
  Tests/OpenClawTests/  # Unit tests (config, error, oauth, token, UI state)
  build.sh              # Compiles Swift → .app bundle → .dmg
  scripts/              # Build helpers (icon generation)
docs/plan/              # Planning docs (testing strategy, etc.)
dist/                   # Build output (.app, .dmg)
```

## Build Commands

```bash
# Build the macOS .app and .dmg
cd app/macos && bash build.sh
# Output: dist/OpenClawLauncher.app, dist/OpenClawLauncher.dmg (at repo root)

# Swift build only (no .app bundle)
cd app/macos && swift build -c release

# Run tests
cd app/macos && swift test
```

## Architecture

The app is split into a library target (`OpenClawLib`) and an executable target (`OpenClawApp`).

### OpenClawApp (`Sources/OpenClawApp/main.swift`)
- `OpenClawApp` — `@main` entry, creates a 520x520/580 animated window + `MenuBarExtra` with status indicator

### OpenClawLib (`Sources/OpenClawLib/`)

**Models.swift** — Data types:
- `StepStatus`, `LauncherState`, `MenuBarStatus` enums
- `GatewayStatus` (Codable, for health check API)
- `LaunchStep`, `ShellResult`, `LauncherError`

**LauncherViews.swift** — SwiftUI views:
- `LauncherView` — gradient header, routes to `DashboardView` (running) or `SetupView` (setup/auth/error)
- `DashboardView` — container status card, uptime timer, tip card, quick actions, collapsible token
- `SetupView` — progress bar with current step, completed count, auth flow views
- `StatusCard` — generic card component
- `MenuBarContent` — menu bar dropdown (Open UI, Restart, Stop, Logs, Show Window, Quit)
- `AuthChoiceView`, `ApiKeyInputView`, `OAuthCodeInputView` — extracted auth views

**OpenClawLauncher.swift** — `@MainActor ObservableObject` viewmodel:
1. `checkDocker()` — validates Docker; auto-installs and starts Docker Desktop on macOS (90s timeout)
2. `firstRunSetup()` — migrates old state dir, generates 64-char hex token, creates `~/.openclaw-launcher/` with `.env` and `openclaw.json`
3. `ensureImage()` — `docker pull ghcr.io/openclaw/openclaw:latest`
4. `runContainer()` — launches container with lockdown security flags
5. `waitForGateway()` — polls `localhost:18789` (30 attempts, 1s apart)
6. Health check system: `startHealthCheck()` / `stopHealthCheck()` / `checkGatewayHealth()` with 5s polling
7. Uptime timer: `uptimeTick` incremented every 1s, drives `uptimeString` computed property
8. `restartContainer()` — with error handling, resets health state
9. `stopContainer()` — clears steps, resets timers

**AnthropicOAuth.swift** — PKCE OAuth flow for Anthropic sign-in

**Docker image**: Uses upstream `ghcr.io/openclaw/openclaw:latest` (multi-arch). The launcher applies lockdown security flags at `docker run` time.

**User data** persists in `~/.openclaw-launcher/` with subdirs `config/` and `workspace/`, mounted into the container.

## Key Design Decisions

- Uses the upstream Docker image (`ghcr.io/openclaw/openclaw:latest`) — no custom Dockerfile needed
- The Swift app uses `Process` for async shell execution via `Task.detached` for pipe reading
- Container runs in lockdown mode: `--read-only`, `--cap-drop ALL`, `--no-new-privileges`, `--memory 2g`, `--pids-limit 256`, localhost-only port binding
- Gateway token is auto-generated on first run and stored in `~/.openclaw-launcher/.env`
- Dashboard/setup split: running state shows dashboard with health + actions; setup state shows progress bar
- Menu bar extra provides persistent status indicator and quick actions even when window is closed
