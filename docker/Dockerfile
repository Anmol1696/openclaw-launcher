# ============================================================================
#  OpenClaw Launcher — Slim Docker Images via npm install
#
#  Targets:  slim, base, full
#  Usage:    docker build --target base -t openclaw-launcher:base .
#
#  Size comparison (vs 4GB upstream):
#    slim: ~300MB  (no local LLM)
#    base: ~500MB  (with node-llama-cpp)
#    full: ~1.2GB  (+ Python + Playwright)
# ============================================================================

# --------------------------------------------------------------------------
#  Stage 1: builder — compile native modules
#
#  Uses full node image with build tools to compile:
#  - node-llama-cpp (requires cmake, clang)
#  - @napi-rs/canvas (prebuilt binaries available)
# --------------------------------------------------------------------------
FROM node:22-bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    cmake \
    clang \
    libgomp1 \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Install openclaw globally with peer dependencies
# node-llama-cpp requires compilation (cmake/clang)
RUN npm install -g openclaw node-llama-cpp@3.15.1 @napi-rs/canvas

# --------------------------------------------------------------------------
#  Stage 2: slim — minimal runtime (no local LLM)
#
#  Smallest image for users who only use cloud APIs.
#  Does not include node-llama-cpp.
# --------------------------------------------------------------------------
FROM node:22-bookworm-slim AS slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    tini \
    jq \
    ripgrep \
    fd-find \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/fdfind /usr/bin/fd

# Copy global node_modules (openclaw only, no llama)
COPY --from=builder /usr/local/lib/node_modules/openclaw /usr/local/lib/node_modules/openclaw
COPY --from=builder /usr/local/lib/node_modules/@napi-rs /usr/local/lib/node_modules/@napi-rs

# Create symlink for openclaw CLI
RUN ln -sf /usr/local/lib/node_modules/openclaw/openclaw.mjs /usr/local/bin/openclaw

# Create non-root user for runtime
RUN groupadd -r openclaw && useradd -r -g openclaw -d /home/openclaw openclaw \
    && mkdir -p /home/openclaw/.openclaw \
    && chown -R openclaw:openclaw /home/openclaw

ENV NODE_ENV=production
WORKDIR /home/openclaw
USER openclaw

ENTRYPOINT ["tini", "--"]
CMD ["openclaw", "gateway", "--allow-unconfigured"]

# --------------------------------------------------------------------------
#  Stage 3: base — slim + local LLM support (recommended default)
#
#  Includes node-llama-cpp for local model inference.
#  Future-proof for offline/local LLM use cases.
# --------------------------------------------------------------------------
FROM slim AS base

USER root

# libgomp1 is required by node-llama-cpp at runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Copy node-llama-cpp (compiled in builder)
COPY --from=builder /usr/local/lib/node_modules/node-llama-cpp /usr/local/lib/node_modules/node-llama-cpp

USER openclaw

# --------------------------------------------------------------------------
#  Stage 4: full — base + Python + Playwright + media tools
#
#  For power users who need:
#  - Python data stack (pandas, matplotlib, Pillow)
#  - Browser automation (Playwright + Chromium)
#  - Media processing (ffmpeg)
# --------------------------------------------------------------------------
FROM base AS full

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    ffmpeg \
    # Chromium runtime dependencies
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libpango-1.0-0 \
    libcairo2 \
    libasound2 \
    libatspi2.0-0 \
    libxshmfence1 \
    && rm -rf /var/lib/apt/lists/*

# Install Python data science packages
RUN python3 -m pip install --no-cache-dir --break-system-packages \
    pandas \
    matplotlib \
    Pillow

# Install Playwright and Chromium browser
RUN npm install -g playwright \
    && npx playwright install chromium \
    && npm cache clean --force

USER openclaw
