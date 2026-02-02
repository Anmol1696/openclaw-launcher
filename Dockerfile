# ============================================================================
#  OpenClaw Gateway — Hardened Docker Image
#  Multi-stage, non-root, minimal attack surface.
# ============================================================================

# --- Stage 1: Install OpenClaw ---
FROM node:22-slim AS builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g openclaw@latest 2>&1 \
    && npm cache clean --force

# --- Stage 2: Minimal runtime ---
FROM node:22-slim

# Only what's strictly needed at runtime
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        tini \
    && apt-get purge -y --auto-remove \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && rm -rf /usr/share/doc /usr/share/man

# Add node user to openclaw group
RUN groupadd -r openclaw \
    && usermod -a -G openclaw node

# Copy only OpenClaw from builder (no npm cache, no build tools)
COPY --from=builder /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=builder /usr/local/bin/openclaw /usr/local/bin/openclaw

# Writable dirs — everything else can be read-only via --read-only flag
RUN mkdir -p /home/node/.openclaw/workspace /home/node/.openclaw/logs /tmp/openclaw \
    && chown -R node:openclaw /home/node /tmp/openclaw

LABEL org.opencontainers.image.title="OpenClaw Gateway (Hardened)"

USER node
WORKDIR /home/node
EXPOSE 18789

HEALTHCHECK --interval=20s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -sf http://127.0.0.1:18789/ || exit 1

ENTRYPOINT ["tini", "--"]
CMD ["openclaw", "gateway", "--bind", "lan", "--port", "18789"]

