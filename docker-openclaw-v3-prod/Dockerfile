# ============================================================
# Stage 1: Build (full toolchain, discarded after build)
# ============================================================
FROM node:22-bookworm AS builder

ARG OPENCLAW_VERSION=main

# Bun (required by OpenClaw build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /app

# Clone and build OpenClaw
RUN git clone --depth 1 --branch ${OPENCLAW_VERSION} https://github.com/openclaw/openclaw.git . \
    && pnpm install --frozen-lockfile

# Apply Claude Agent SDK customizations from private repo
RUN --mount=type=secret,id=github_token \
    GITHUB_TOKEN="$(cat /run/secrets/github_token 2>/dev/null || true)" \
    && if [ -n "$GITHUB_TOKEN" ]; then \
        git clone --depth 1 https://${GITHUB_TOKEN}@github.com/iammarcin/openclaw-custom-claude-sdk.git /tmp/sdk-patches; \
    else \
        git clone --depth 1 https://github.com/iammarcin/openclaw-custom-claude-sdk.git /tmp/sdk-patches; \
    fi \
    && mkdir -p src/agents/claude-sdk src/config \
    && cp /tmp/sdk-patches/src/agents/claude-sdk/run.ts src/agents/claude-sdk/run.ts \
    && cp /tmp/sdk-patches/src/agents/claude-sdk/run-cli.ts src/agents/claude-sdk/run-cli.ts \
    && cp /tmp/sdk-patches/src/agents/claude-sdk/cli-helpers.ts src/agents/claude-sdk/cli-helpers.ts \
    && cp /tmp/sdk-patches/src/agents/claude-sdk/ndjson-parser.ts src/agents/claude-sdk/ndjson-parser.ts \
    && cp /tmp/sdk-patches/src/agents/claude-sdk/thinking-state-machine.ts src/agents/claude-sdk/thinking-state-machine.ts \
    && cp /tmp/sdk-patches/src/agents/pi-embedded.ts src/agents/pi-embedded.ts \
    && cp /tmp/sdk-patches/src/config/zod-schema.agents.ts src/config/zod-schema.agents.ts \
    && cp /tmp/sdk-patches/src/config/zod-schema.agent-runtime.ts src/config/zod-schema.agent-runtime.ts \
    && cp /tmp/sdk-patches/src/config/types.agents.ts src/config/types.agents.ts \
    && rm -rf /tmp/sdk-patches \
    && pnpm add -w @anthropic-ai/claude-agent-sdk

# Build and prune to production-only dependencies
RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build \
    && OPENCLAW_PREFER_PNPM=1 pnpm ui:build \
    && CI=true pnpm prune --prod

# Strip build-only artifacts before copy to runtime stage
RUN rm -rf .git .turbo

# ============================================================
# Stage 2: Runtime (minimal, no browser/VNC/Python/desktop)
# ============================================================
FROM node:22-bookworm-slim

ARG OPENCLAW_DOCKER_APT_PACKAGES=""

# Minimal runtime dependencies only
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    openssl \
    curl \
    git \
    procps \
    && if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES; \
    fi \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Claude Code binary
SHELL ["/bin/bash", "-c"]
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && cp "$(readlink -f /root/.local/bin/claude)" /usr/local/bin/claude \
    && chmod +x /usr/local/bin/claude \
    && rm -rf /root/.local /root/.cache
SHELL ["/bin/sh", "-c"]

# pnpm (OpenClaw uses it at runtime)
RUN corepack enable

WORKDIR /app

# Copy only the built application from builder (no build tools, no .git)
COPY --from=builder /app /app

# Global command alias
RUN ln -s /app/openclaw.mjs /usr/local/bin/openclaw

COPY start.sh /start.sh
RUN chmod +x /start.sh

# Runtime environment
ENV NODE_ENV=production
ENV HOME=/home/node
ENV OPENCLAW_PREFER_PNPM=1
ENV NODE_COMPILE_CACHE=/home/node/.cache/node-compile

# Pre-warm Node compile cache
RUN mkdir -p /home/node/.cache/node-compile \
    && node openclaw.mjs --version 2>/dev/null || true

RUN mkdir -p /home/node/.openclaw /home/node/.openclaw/workspace \
    /home/node/.claude \
    && chown -R node:node /app /home/node

EXPOSE 18789

ENTRYPOINT ["/bin/bash"]
CMD ["/start.sh"]
