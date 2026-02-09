# OpenClaw Launcher - Development Plans

This directory contains planning documents for launcher improvements.

## Plan Files

| File | Description | Branch Suggestion |
|------|-------------|-------------------|
| [current-state.md](current-state.md) | Current architecture, features, gaps | N/A (reference) |
| [ui-revamp.md](ui-revamp.md) | **Deep Ocean theme UI rebuild (100 tasks)** | `feat/ui-*` |
| [distribution.md](distribution.md) | DMG signing, Sparkle auto-updates | `feat/distribution` |
| [auth-improvements.md](auth-improvements.md) | OAuth URL scheme | `feat/oauth-url-scheme` |
| [observability.md](observability.md) | Sentry, pull progress, log streaming | `feat/observability` |
| [user-preferences.md](user-preferences.md) | Settings, keyboard shortcuts | `feat/settings` |
| [testing.md](testing.md) | Integration testing (implemented) | N/A (done) |

---

## Priority Overview

### Phase 1: Quick Wins (30 min)
- [ ] DMG signing (`distribution.md`)
- [ ] Keyboard shortcuts (`user-preferences.md`)

### Phase 2: Foundation (2 hrs)
- [ ] Docker pull progress (`observability.md`)
- [ ] Settings persistence (`user-preferences.md`)

### Phase 3: Auth UX (2 hrs)
- [ ] OAuth URL scheme (`auth-improvements.md`)

### Phase 4: Distribution (4 hrs)
- [ ] Sparkle auto-updates (`distribution.md`)

### Phase 5: Production (2 hrs)
- [ ] Sentry crash reporting (`observability.md`)

### Phase 6: UI Revamp (~25 hrs)
See [ui-revamp.md](ui-revamp.md) for detailed 100-task breakdown:
- [ ] Foundation: Theme + base components
- [ ] Main Window: 4 states (idle, starting, running, stopping)
- [ ] Error States: Docker, pull, port, crash handling
- [ ] Settings: Tabbed window (General, Container, Advanced)
- [ ] Supporting: Logs, menu bar, modals
- [ ] Onboarding: 3-step first-run wizard
- [ ] Cleanup: Remove old UI, polish

---

## Deferred Items

| Item | Reason |
|------|--------|
| Notarization | Apple servers stuck "In Progress" |

---

## Branch Strategy

Each plan file can be worked on independently:

```bash
# UI Revamp (in order)
git checkout -b feat/ui-foundation    # Theme + base components
git checkout -b feat/ui-main-states   # Main window states
git checkout -b feat/ui-error-states  # Error handling
git checkout -b feat/ui-settings      # Settings window
git checkout -b feat/ui-supporting    # Logs, menu bar, modals
git checkout -b feat/ui-onboarding    # First-run wizard
git checkout -b feat/ui-polish        # Cleanup

# Non-UI improvements
git checkout -b feat/distribution     # DMG signing, Sparkle
git checkout -b feat/oauth-url-scheme # Better auth flow
git checkout -b feat/observability    # Sentry, pull progress
```

---

## Estimated Total Effort

| Phase | Items | Effort |
|-------|-------|--------|
| Quick Wins | DMG signing, shortcuts | 30 min |
| Foundation | Pull progress, settings model | 1.5 hrs |
| Auth UX | OAuth URL scheme | 2 hrs |
| Distribution | Sparkle | 3-4 hrs |
| Production | Sentry | 2 hrs |
| **Total (non-UI)** | | **~10-12 hrs** |
| | | |
| UI Foundation | Theme + components | 4-6 hrs |
| UI Main Window | 4 states | 4-6 hrs |
| UI Error States | Error handling | 2-3 hrs |
| UI Settings | Tabbed window | 3-4 hrs |
| UI Supporting | Logs, menu bar, modals | 4-5 hrs |
| UI Onboarding | First-run wizard | 2-3 hrs |
| **Total (UI)** | | **~20-27 hrs** |

---

## External Dependencies

| Item | Setup Required |
|------|----------------|
| Sparkle | Generate EdDSA keys, host appcast |
| Sentry | Create account, get DSN |
| Notarization | Wait for Apple servers |

---

## Related Files

- `CLAUDE.md` - Codebase reference for AI assistants
- `.github/workflows/publish.yml` - CI/CD pipeline
- `app/macos/build.sh` - Build script
