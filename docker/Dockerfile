# ============================================================================
#  OpenClaw Launcher — Multi-stage, multi-flavor Docker build
#
#  Targets:  base, lite, full
#  Usage:    docker build --target base -t openclaw-launcher:base .
# ============================================================================

# --------------------------------------------------------------------------
#  Stage 0: upstream — use the official image as a pre-built source
# --------------------------------------------------------------------------
FROM ghcr.io/openclaw/openclaw:latest AS upstream

# --------------------------------------------------------------------------
#  Stage 1: base — slim runtime + core CLI tools
#
#  Strips build tooling (gcc, g++, bun, dev headers, pnpm cache) that the
#  upstream single-stage image ships but doesn't need at runtime.
#  Adds: jq, ripgrep, fd, sqlite3
# --------------------------------------------------------------------------
FROM node:22-bookworm-slim AS base

RUN apt-get update && apt-get install -y --no-install-recommends \
    tini \
    jq \
    ripgrep \
    fd-find \
    sqlite3 \
    # runtime libs the app's native modules link against
    libvips42 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/fdfind /usr/bin/fd

WORKDIR /app

# Copy only the built app from upstream — no compilers, no source, no cache
COPY --from=upstream /app/dist        ./dist
COPY --from=upstream /app/node_modules ./node_modules
COPY --from=upstream /app/ui          ./ui
COPY --from=upstream /app/package.json ./package.json
COPY --from=upstream /app/patches     ./patches
COPY --from=upstream /app/scripts     ./scripts

ENV NODE_ENV=production
ENV PATH="/app/node_modules/.bin:${PATH}"

RUN chown -R node:node /app

USER node

ENTRYPOINT ["tini", "--"]
CMD ["node", "dist/index.js", "gateway", "--allow-unconfigured"]

# --------------------------------------------------------------------------
#  Stage 2: lite — base + Python data stack
#
#  Adds: Python 3, pandas, matplotlib, Pillow
# --------------------------------------------------------------------------
FROM base AS lite

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m pip install --no-cache-dir --break-system-packages \
    pandas matplotlib Pillow

USER node

# --------------------------------------------------------------------------
#  Stage 3: full — lite + media + browser automation
#
#  Adds: ffmpeg, Playwright + Chromium
# --------------------------------------------------------------------------
FROM lite AS full

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    # Chromium runtime deps (what --with-deps would install, but done here
    # in a single apt layer to avoid stale GPG cache issues)
    libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 \
    libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
    libgbm1 libpango-1.0-0 libcairo2 libasound2 libatspi2.0-0 \
    libxshmfence1 \
    && rm -rf /var/lib/apt/lists/*

# Install playwright CLI + download Chromium binary (no --with-deps needed)
RUN npm install -g playwright \
    && playwright install chromium

USER node
