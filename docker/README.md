# OpenClaw Launcher Docker Images

Multi-stage Dockerfile that extends the upstream
[`ghcr.io/openclaw/openclaw`](https://github.com/openclaw/openclaw) image,
strips build tooling (~200MB+ of compilers and dev headers), and layers on
useful runtime tools.

## Flavors

| Flavor | Target | What's included | Est. image size |
|--------|--------|----------------|-----------------|
| **base** | `base` | jq, ripgrep, fd, sqlite3 | ~350 MB |
| **lite** | `lite` | base + Python 3, pandas, matplotlib, Pillow | ~700 MB |
| **full** | `full` | lite + ffmpeg, Playwright + Chromium | ~1.4 GB |

Compared to the upstream image (~800MB with build tools), **base** is
significantly smaller because it copies only the built app into
`node:22-bookworm-slim` and drops gcc, g++, bun, pnpm cache, and dev headers.

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

All flavors are build targets in a single `docker/Dockerfile`:

```bash
# Build base
docker build --target base -f docker/Dockerfile -t openclaw-launcher:base .

# Build lite
docker build --target lite -f docker/Dockerfile -t openclaw-launcher:lite .

# Build full
docker build --target full -f docker/Dockerfile -t openclaw-launcher:full .
```

## Verify

```bash
docker run --rm openclaw-launcher:base jq --version
docker run --rm openclaw-launcher:base rg --version
docker run --rm openclaw-launcher:base fd --version
docker run --rm openclaw-launcher:base sqlite3 --version
docker run --rm openclaw-launcher:lite python3 -c "import pandas; print(pandas.__version__)"
docker run --rm openclaw-launcher:full ffmpeg -version
```

## Using a flavor

```bash
# Shell launcher
OPENCLAW_FLAVOR=full ./run.sh

# Or set in environment
export OPENCLAW_FLAVOR=lite
./run.sh
```

The macOS app uses `base` by default.
