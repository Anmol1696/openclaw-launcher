# OpenClaw Launcher Docker Images

Slim Docker images that install OpenClaw directly via npm, bypassing the bloated
4GB upstream image. Multi-stage build compiles native modules once, then copies
only runtime artifacts to a minimal base.

## Flavors

| Flavor | Target | What's included | Image size |
|--------|--------|----------------|------------|
| **slim** | `slim` | OpenClaw + jq, ripgrep, fd, sqlite3 | ~300 MB |
| **base** | `base` | slim + node-llama-cpp (local LLM support) | ~500 MB |
| **full** | `full` | base + Python 3, Playwright + Chromium, ffmpeg | ~1.2 GB |

**Recommended:** Use `base` for future-proof local LLM support, or `slim` if you
only use cloud APIs and want the smallest possible image.

## How it works

Instead of extending the 4GB upstream image, we:

1. **Builder stage**: Install build tools (cmake, clang) and compile native modules
   - `openclaw` (~56MB npm package)
   - `node-llama-cpp` (~30MB, requires compilation)
   - `@napi-rs/canvas` (prebuilt binaries)

2. **Runtime stage**: Copy only compiled modules to `node:22-bookworm-slim`
   - No compilers, no dev headers, no build cache
   - Just the runtime libs needed by native modules

Result: **70% smaller** than upstream (500MB vs 4GB).

## Tool inventory

### slim
- **jq** — JSON processor (API responses, config manipulation)
- **ripgrep** (`rg`) — fast recursive search
- **fd** — fast file finder (aliased from `fd-find`)
- **sqlite3** — embedded SQL database
- **tini** — proper PID 1 signal handling

### base (includes slim)
- **node-llama-cpp** — local LLM inference (CPU)
- **libgomp1** — OpenMP runtime for parallel processing

### full (includes base)
- **Python 3** with pip
- **pandas** — data analysis
- **matplotlib** — charts and plots
- **Pillow** — image processing
- **ffmpeg** — video/audio/image conversion
- **Playwright + Chromium** — headless browser automation

## Building locally

All flavors are build targets in a single `docker/Dockerfile`. Use the Makefile:

```bash
cd docker

make help              # Show all targets

make build             # Build base (default)
make build FLAVOR=slim # Build slim
make build-all         # Build all flavors

make verify            # Verify base tools
make verify-all        # Verify all flavors

make shell             # Shell into base
make shell FLAVOR=full # Shell into full

make run               # Run base (gateway on localhost:18789)
make run FLAVOR=slim   # Run slim

make clean             # Remove all local images
```

### Raw docker commands

```bash
docker build --target slim -f docker/Dockerfile -t openclaw-launcher:slim .
docker build --target base -f docker/Dockerfile -t openclaw-launcher:base .
docker build --target full -f docker/Dockerfile -t openclaw-launcher:full .
```

### Check image sizes

```bash
docker images openclaw-launcher
```

## Using a flavor

```bash
# Shell launcher
OPENCLAW_FLAVOR=base ./scripts/run.sh

# Or set in environment
export OPENCLAW_FLAVOR=slim
./scripts/run.sh
```

## Verification

```bash
# Test gateway starts
docker run --rm -p 18789:18789 openclaw-launcher:base
# Visit http://localhost:18789

# Test local LLM module loads (base/full only)
docker run --rm openclaw-launcher:base node -e "require('node-llama-cpp')"
```

## Multi-arch

```bash
make build-multiarch          # Validate multi-arch build (no load)
make build-multiarch-all      # Validate all flavors
make push FLAVOR=base         # Build + push to GHCR (requires login)
make push-all                 # Push all flavors
```
