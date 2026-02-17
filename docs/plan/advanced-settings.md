# Advanced Settings Plan

Future settings panel for the macOS app — image selection, resource tuning, and environment presets.

## Current State

All Docker configuration is hardcoded:

| Setting | Value | Location |
|---------|-------|----------|
| Image | `ghcr.io/constructive-io/openclaw-launcher:base` | `OpenClawLauncher.swift:24` |
| Memory | `2g` | `OpenClawLauncher.swift:551` |
| Memory swap | `2g` (no swap) | `OpenClawLauncher.swift:552` |
| CPUs | `2.0` | `OpenClawLauncher.swift:553` |
| PID limit | `256` | `OpenClawLauncher.swift:554` |
| Port | `18789` | `OpenClawLauncher.swift:25` |

No settings UI exists. The shell launcher (`run.sh`) already supports `OPENCLAW_FLAVOR` and `OPENCLAW_PORT` env vars.

---

## 1. Image Selection

### Flavor picker

Dropdown with the three built-in flavors:

| Flavor | Tools | Image size | Use case |
|--------|-------|------------|----------|
| **base** | jq, ripgrep, fd, sqlite3 | 1.65 GB | API calls, file search, data storage |
| **lite** | base + Python 3, pandas, matplotlib, Pillow | 1.96 GB | Data analysis, charts, image processing |
| **full** | lite + ffmpeg, Playwright + Chromium | 3.28 GB | Browser automation, video/audio processing |

Each option shows:
- Tool list
- Image size
- Brief description of what it unlocks

### Bring your own image

Text field for a custom Docker image (e.g. `myregistry/my-openclaw:custom`).

Requirements for compatibility:
- Must have `node` binary in PATH
- Must have `/app/dist/index.js` (the OpenClaw gateway)
- Must support `node dist/index.js gateway --bind lan --port 18789` as CMD
- Should run as non-root user (will work as root but defeats lockdown security)

Validation flow:
1. Pull the image (`docker pull`)
2. Quick sanity check: `docker run --rm <image> node --version`
3. If valid, save and offer to restart container

---

## 2. Environment Presets

Pre-configured profiles that bundle image + resources:

| Preset | Image | RAM | CPUs | PIDs | Best for |
|--------|-------|-----|------|------|----------|
| **Minimal** | base | 1 GB | 1.0 | 128 | Lightweight tasks, API-only usage, low-resource machines |
| **Standard** | base | 2 GB | 2.0 | 256 | General use (current default) |
| **Data Science** | lite | 4 GB | 2.0 | 256 | pandas analysis, matplotlib charts, Pillow image work |
| **Full Stack** | full | 4 GB | 4.0 | 512 | Browser automation, media processing, everything |
| **Custom** | user choice | user choice | user choice | user choice | Power users |

Selecting a preset auto-fills all fields. Switching to Custom unlocks individual controls.

---

## 3. Resource Controls

Available when preset is Custom, or as overrides on any preset.

### RAM

- Slider: 512 MB → 8 GB
- Default: 2 GB
- Step: 256 MB
- Maps to `--memory` and `--memory-swap` (set equal = no swap)
- Show host total RAM as reference (e.g. "of 16 GB available")

### CPUs

- Slider: 0.5 → host max cores
- Default: 2.0
- Step: 0.5
- Maps to `--cpus`
- Show host core count as reference (e.g. "of 10 cores available")

### PID limit

- Slider: 128 → 1024
- Default: 256
- Step: 64
- Maps to `--pids-limit`
- Most users won't touch this

### Warnings

- Allocating >50% of host RAM: yellow warning
- Allocating >75% of host RAM: red warning with "your system may become unresponsive"
- Full flavor with <3 GB RAM: warn that Chromium may crash

---

## 4. Configuration Storage

### New file: `~/.openclaw-launcher/config/launcher.json`

```json
{
  "image": "ghcr.io/constructive-io/openclaw-launcher:base",
  "preset": "standard",
  "resources": {
    "memory": "2g",
    "cpus": 2.0,
    "pidsLimit": 256
  }
}
```

- Created on first settings change (doesn't exist by default = use hardcoded defaults)
- `chmod 600` for consistency with other config files
- Read at launch by `OpenClawLauncher.swift`, merged over defaults
- If file is malformed or missing fields, fall back to defaults per-field

### Shell launcher (`run.sh`)

Extend with env vars matching each setting:

```bash
IMAGE_NAME="ghcr.io/constructive-io/openclaw-launcher:${OPENCLAW_FLAVOR:-base}"
MEMORY="${OPENCLAW_MEMORY:-2g}"
CPUS="${OPENCLAW_CPUS:-2.0}"
PIDS_LIMIT="${OPENCLAW_PIDS_LIMIT:-256}"
```

---

## 5. UI Location

### Option A: Settings section in dashboard (simpler)

Add a collapsible "Advanced Settings" section at the bottom of `DashboardView`, with a gear icon. Collapsed by default. Contains:
- Preset picker (segmented control)
- Image dropdown / custom field
- Resource sliders
- "Apply & Restart" button

### Option B: Separate Settings window (more native)

Menu bar → Settings (or `⌘,`). Opens a standard macOS Settings window (`Settings` scene in SwiftUI). Tabs:
- General (image, preset)
- Resources (RAM, CPU, PIDs)

### Recommendation: Option A

Keeps everything in one window. The app is simple enough that a separate settings window adds unnecessary navigation. A collapsible section keeps it hidden until needed.

### Restart flow

Any change to image or resources requires a container restart:
1. User changes a setting
2. "Apply & Restart" button enables
3. On click: confirmation dialog ("This will restart the container. Continue?")
4. Stop container → apply new settings → start container
5. Progress bar shows during restart

---

## Implementation Order

1. Add `LauncherSettings` struct to `Models.swift` (Codable, with defaults)
2. Add settings read/write to `OpenClawLauncher.swift`
3. Replace hardcoded values in `runContainer()` with settings
4. Add settings UI to `LauncherViews.swift`
5. Extend `run.sh` with env vars
6. Tests for settings serialization and defaults

---

## Files to modify (when implementing)

| File | Change |
|------|--------|
| `app/macos/Sources/OpenClawLib/Models.swift` | Add `LauncherSettings`, `EnvironmentPreset` |
| `app/macos/Sources/OpenClawLib/OpenClawLauncher.swift` | Load/save settings, use in docker run |
| `app/macos/Sources/OpenClawLib/LauncherViews.swift` | Settings section in dashboard |
| `run.sh` | `OPENCLAW_MEMORY`, `OPENCLAW_CPUS`, `OPENCLAW_PIDS_LIMIT` env vars |
| `app/macos/Tests/OpenClawTests/` | Settings serialization tests |
