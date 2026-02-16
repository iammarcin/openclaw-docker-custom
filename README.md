# OpenClaw Docker - Production Deployment with Claude Agent SDK

A production-ready, multi-stage Docker setup for [OpenClaw](https://github.com/openclaw/openclaw) — an open-source AI agent orchestration platform — extended with a custom [Claude Agent SDK](https://docs.anthropic.com/en/docs/agents-and-tools/claude-agent-sdk) integration for running Anthropic-powered AI agents.

## What This Project Does

This repository packages OpenClaw into a lean, self-contained Docker deployment that:

- **Builds OpenClaw from source** using a multi-stage Dockerfile (build toolchain is discarded, runtime image stays minimal)
- **Injects custom Claude Agent SDK modules** at build time from a [companion repository](https://github.com/iammarcin/openclaw-custom-claude-sdk), adding a full Claude-based agent engine with thinking state machine, NDJSON streaming, and CLI helpers
- **Auto-onboards on first run** — generates gateway tokens, wires up auth profiles, and starts the gateway with zero manual config steps
- **Exposes a web UI and WebSocket gateway** for connecting external backends, CLIs, and other clients to AI agents

## Architecture

```
┌──────────────────────────────────────────────────┐
│  docker-compose.yml                              │
│                                                  │
│  ┌────────────────────┐  ┌────────────────────┐  │
│  │  openclaw (gateway) │  │  claude-auth       │  │
│  │  Web UI :18789      │  │  Claude Code login │  │
│  │  WebSocket gateway  │  │  (on-demand)       │  │
│  └────────────────────┘  └────────────────────┘  │
│                                                  │
│  ┌────────────────────┐                          │
│  │  openclaw-cli       │                          │
│  │  Interactive CLI    │                          │
│  └────────────────────┘                          │
│                                                  │
│  Volumes:  config/ · workspace/ · claude-creds/  │
│  Network:  betterai-network (external)           │
└──────────────────────────────────────────────────┘
```

| Service | Purpose |
|---|---|
| `openclaw` | Main gateway — serves the web UI and the WebSocket API that agents and backends connect to |
| `openclaw-cli` | On-demand CLI for managing agents, devices, and config from the terminal |
| `claude-auth` | One-shot helper to authenticate Claude Code (runs `claude setup-token`) |

## Key Implementation Details

**Multi-stage Docker build** — the builder stage installs Node 22, Bun, pnpm, clones OpenClaw, applies SDK patches, and builds everything. The runtime stage starts from `node:22-bookworm-slim` and carries only production dependencies, the compiled app, and Claude Code CLI. No build tools, no `.git` history, no dev dependencies in the final image.

**Custom Claude Agent SDK integration** — at build time, the Dockerfile pulls agent modules (thinking state machine, NDJSON parser, CLI helpers) from a separate repo and overlays them onto the OpenClaw source tree before compilation. This keeps customizations version-controlled and reproducible without forking OpenClaw itself.

**Zero-touch first boot** — `start.sh` detects a missing config, runs non-interactive onboarding, generates a secure gateway token, injects API key auth profiles, syncs remote tokens, and starts the gateway. The container goes from `docker compose up` to a working agent platform with no manual steps.

**Token-based device pairing** — localhost connections (via `docker exec`) are auto-approved; external clients go through a pairing approval flow. The POST-INSTALL guide documents the full token lifecycle.

## Quick Start

### Prerequisites

- Docker and Docker Compose
- An external Docker network: `docker network create betterai-network`
- Anthropic API key **or** Claude Code subscription credentials

### 1. Configure environment

```bash
cd docker-openclaw-v3-prod
cp .env .env.local   # edit as needed
```

Set `ANTHROPIC_API_KEY` in `.env` for API key auth, or leave it empty and use Claude Code subscription auth (Step 3).

### 2. Build and start

```bash
docker compose build
docker compose up -d openclaw
```

Wait ~30 seconds for auto-onboard to complete, then check the logs:

```bash
docker logs openclaw-prod
```

You should see the startup banner with the gateway token and Web UI URL.

### 3. (Optional) Authenticate Claude Code subscription

If using a Claude subscription instead of an API key:

```bash
docker compose run --rm claude-auth
```

### 4. Verify

```bash
# Open the web UI
open http://localhost:18789

# Or use the CLI
docker exec -u node openclaw-prod node /app/openclaw.mjs gateway status \
  --url ws://127.0.0.1:18789 --token <TOKEN_FROM_LOGS>
```

See [POST-INSTALL.md](docker-openclaw-v3-prod/POST-INSTALL.md) for device pairing, backend integration, token management, and troubleshooting.

## Project Structure

```
docker-openclaw-v3-prod/
├── Dockerfile                  # Multi-stage build (builder + minimal runtime)
├── docker-compose.yml          # Three services: gateway, CLI, auth helper
├── start.sh                    # Entrypoint: auto-onboard, token sync, gateway start
├── openclaw.json.template      # Config skeleton with agent and gateway defaults
├── .env                        # Environment variables (API keys, ports, paths)
├── .gitignore                  # Excludes sensitive runtime data
└── POST-INSTALL.md             # Step-by-step setup and troubleshooting guide
```

## Tech Stack

- **Docker** — multi-stage builds, Compose, secrets management
- **Node.js 22** — runtime for OpenClaw and agent processes
- **OpenClaw** — open-source AI agent orchestration (gateway, WebSocket API, device pairing)
- **Claude Agent SDK** — Anthropic's SDK for building Claude-powered agents
- **Claude Code** — Anthropic's CLI, installed in the container for agent execution
- **pnpm / Bun** — package management and build tooling
- **Bash** — entrypoint scripting with automatic provisioning

## Related Repository

- [openclaw-custom-claude-sdk](https://github.com/iammarcin/openclaw-custom-claude-sdk) — the custom Claude Agent SDK modules injected at build time (agent engine, thinking state machine, streaming parser)
