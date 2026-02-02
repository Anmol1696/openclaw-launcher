# OpenClaw Launcher Docker Images

Multi-stage Dockerfile that extends the upstream
[`ghcr.io/openclaw/openclaw`](https://github.com/openclaw/openclaw) image,
strips build tooling (~940MB of compilers and dev headers), and layers on
useful runtime tools.

## Flavors

| Flavor | Target | What's included | Image size |
|--------|--------|----------------|------------|
| **base** | `base` | jq, ripgrep, fd, sqlite3 | 1.65 GB |
| **lite** | `lite` | base + Python 3, pandas, matplotlib, Pillow | 1.96 GB |
| **full** | `full` | lite + ffmpeg, Playwright + Chromium | 3.28 GB |
| *upstream* | — | *build tools included, no extra CLI tools* | *2.59 GB* |

**base** is ~940MB smaller than upstream despite adding extra tools, because the
multi-stage build copies only the built app into `node:22-bookworm-slim` and
drops gcc, g++, bun, pnpm cache, and dev headers.

## What's stripped from upstream

The upstream image uses a single-stage build on `node:22-bookworm` (full
Debian). It ships compilers and dev headers that are only needed during
`pnpm install`:

- GCC / G++ / CPP (~120 MB)
- libicu-dev, libssl-dev, libglib2.0-dev (dev headers, ~60 MB)
- Bun (~30 MB, only used for build scripts)
- binutils (~30 MB)
- Mercurial (~15 MB)
- pnpm cache and source code

Our multi-stage build copies only `/app/dist`, `/app/node_modules`, `/app/ui`,
`/app/patches`, `/app/scripts`, and `package.json` into a slim base.

## Tool inventory

### base
- **jq** — JSON processor (API responses, config manipulation)
- **ripgrep** (`rg`) — fast recursive search
- **fd** — fast file finder (aliased from `fd-find`)
- **sqlite3** — embedded SQL database
- **tini** — proper PID 1 signal handling

### lite (includes base)
- **Python 3** with pip and venv
- **pandas** — data analysis
- **matplotlib** — charts and plots
- **Pillow** — image processing

### full (includes lite)
- **ffmpeg** — video/audio/image conversion
- **Playwright + Chromium** — headless browser automation

## Building locally

All flavors are build targets in a single `docker/Dockerfile`. Use the Makefile:

```bash
cd docker

make help              # Show all targets

make build             # Build base (default)
make build FLAVOR=lite # Build lite
make build-all         # Build all flavors

make verify            # Verify base tools
make verify-all        # Verify all flavors

make shell             # Shell into base
make shell FLAVOR=full # Shell into full

make run               # Run base (gateway on localhost:18789)
make run FLAVOR=lite   # Run lite

make clean             # Remove all local images
```

### Multi-arch

```bash
make build-multiarch          # Validate multi-arch build (no load)
make build-multiarch-all      # Validate all flavors
make push FLAVOR=base         # Build + push to GHCR (requires login)
make push-all                 # Push all flavors
```

### Raw docker commands

```bash
docker build --target base -f docker/Dockerfile -t openclaw-launcher:base .
docker build --target lite -f docker/Dockerfile -t openclaw-launcher:lite .
docker build --target full -f docker/Dockerfile -t openclaw-launcher:full .
```

## Using a flavor

```bash
# Shell launcher
OPENCLAW_FLAVOR=full ./run.sh

# Or set in environment
export OPENCLAW_FLAVOR=lite
./run.sh
```

The macOS app currently uses the upstream image. Custom flavor selection and
bring-your-own-image support are coming in a future release via advanced settings.
