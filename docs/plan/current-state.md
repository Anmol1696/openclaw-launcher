# Current State Assessment

## Overview

OpenClaw Launcher is a native macOS SwiftUI application that provides a one-click launcher for the OpenClaw AI Gateway. It manages Docker containers, handles authentication, and provides health monitoring with automatic recovery.

**Codebase Stats:**
- 2,431 lines of Swift code
- 37 tests (all passing)
- ~820 lines of test code (34% coverage)
- Zero external dependencies (stdlib + Foundation only)

**Quality Assessment: 9/10** - Production-ready codebase

---

## Architecture

```
OpenClawApp (executable)
  └── OpenClawApp.swift      # @main, WindowGroup, MenuBarExtra

OpenClawLib (library)
  ├── Models.swift           # Data types, protocols
  ├── LauncherViews.swift    # SwiftUI views
  ├── OpenClawLauncher.swift # @MainActor ObservableObject viewmodel
  └── AnthropicOAuth.swift   # PKCE OAuth flow
```

**Key Design Decisions:**
- Library/executable split for testability
- Protocol-based `ShellExecutor` for mocking Docker commands
- `@MainActor` thread safety with `@Published` reactivity
- No external dependencies - all stdlib/Foundation

---

## Current Features

### Docker Management
- One-click container lifecycle (pull, run, restart, stop)
- Auto-recovery from previous sessions
- Health monitoring (5s polling)
- Lockdown security mode:
  - `--read-only` filesystem
  - `--cap-drop ALL`
  - `--no-new-privileges`
  - Memory/CPU/PID limits
  - Localhost-only binding

### Authentication
- OAuth PKCE flow (Anthropic sign-in)
- API key input (manual entry)
- Skip option (configure later in Control UI)
- Token refresh with expired banner

### User Interface
- Main window with setup/dashboard states
- Menu bar extra with quick actions
- Progress bar during setup
- Log viewer (300-line snapshot)
- Collapsible gateway token display

### First-Run Setup
- Creates `~/.openclaw-launcher/` directory
- Generates 64-char hex security token
- Migrates from old `~/.openclaw-docker/`
- Docker Desktop auto-install prompt (macOS)

---

## Test Coverage

| Test File | Tests | Coverage |
|-----------|-------|----------|
| ConfigTests | 3 | .env parsing, JSON config, migration |
| ErrorTests | 2 | Error descriptions |
| OAuthTests | 4 | PKCE generation, URL construction |
| TokenTests | 3 | Token format, uniqueness |
| UIStateTests | 14 | State machine, progress, uptime |
| LauncherIntegrationTests | 11 | Docker workflow mocking |

**Not Tested (requires real environment):**
- Browser opening
- Docker Desktop auto-launch
- URLSession network requests
- File permissions (chmod)
- Timer-based health checks

---

## Known Gaps

### Distribution (Critical)
- [ ] Notarization (users must `xattr -cr` to bypass Gatekeeper)
- [ ] DMG not code-signed (only .app inside is signed)
- [ ] No auto-update mechanism

### User Experience
- [ ] OAuth requires manual code copy-paste
- [ ] Docker pull shows no progress
- [ ] Static log viewer (no streaming)
- [ ] No keyboard shortcuts
- [ ] No user preferences/settings

### Observability
- [ ] No crash reporting
- [ ] No analytics/telemetry
- [ ] Errors only logged to console

### Polish
- [ ] Static emoji menu bar icon (no state colors)
- [ ] No first-time tooltips
- [ ] No dark mode icon variant

---

## OpenClaw Project Context

OpenClaw (the upstream project) has become one of the fastest-growing open source projects:

- **160,000+ GitHub stars** (Feb 2026)
- Multi-channel messaging: WhatsApp, Discord, Slack, iMessage, etc.
- Local-first, privacy-focused AI assistant
- Model-agnostic (works with any AI, including local models)
- Active security patches (vulnerabilities discovered and fixed)
- Latest version: 2026.2.2

**Recent Developments:**
- Ollama integration for local models
- Openclawd cloud deployment
- MoltBook social network for AI agents

---

## Recommended Priorities

### Phase 1: Quick Wins
- DMG signing
- Keyboard shortcuts

### Phase 2: Foundation
- Settings persistence
- Docker pull progress

### Phase 3: Auth UX
- OAuth URL scheme (eliminate copy-paste)

### Phase 4: Distribution
- Sparkle auto-updates

### Phase 5: Production
- Sentry crash reporting

### Phase 6: Polish (with UI revamp)
- Dynamic menu bar icon
- Settings window
- Log streaming
- First-time onboarding

---

## Files Reference

| Path | Purpose |
|------|---------|
| `app/macos/Package.swift` | Swift package manifest |
| `app/macos/Sources/OpenClawLib/` | Core library |
| `app/macos/Sources/OpenClawApp/` | App entry point |
| `app/macos/Tests/` | Unit + integration tests |
| `app/macos/build.sh` | Build script (.app + .dmg) |
| `app/macos/OpenClawLauncher.entitlements` | Hardened runtime config |
| `.github/workflows/publish.yml` | CI/CD pipeline |
