# OpenClaw Launcher - Development Plans

This directory contains planning documents for launcher improvements.

## Plan Files

| File | Description | Branch Suggestion |
|------|-------------|-------------------|
| [current-state.md](current-state.md) | Current architecture, features, gaps | N/A (reference) |
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

### Phase 6: UI Revamp (TBD)
- [ ] Settings window
- [ ] Log viewer improvements
- [ ] Dynamic menu bar icon
- [ ] First-time onboarding polish

---

## Deferred Items

These items are blocked or deferred:

| Item | Reason |
|------|--------|
| Notarization | Apple servers stuck "In Progress" |
| Settings UI | Waiting for UI revamp |
| Log streaming UI | Waiting for UI revamp |
| Menu bar icon | Waiting for UI revamp |

---

## Branch Strategy

Each plan file can be worked on independently:

```bash
# Distribution improvements
git checkout -b feat/distribution
# Work on distribution.md items

# OAuth URL scheme
git checkout -b feat/oauth-url-scheme
# Work on auth-improvements.md items

# Observability
git checkout -b feat/observability
# Work on observability.md items

# Settings
git checkout -b feat/settings
# Work on user-preferences.md items
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

UI revamp effort is separate and TBD.

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
