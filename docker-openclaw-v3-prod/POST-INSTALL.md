# OpenClaw Docker - Post-Install Procedure

After building and starting the OpenClaw container for the first time, follow these steps.

## What Happens Automatically

When the container starts for the first time, `start.sh` handles:
- Auto-onboard (creates `openclaw.json` with a random gateway token)
- Syncs `gateway.remote.token` = `gateway.auth.token` (so CLI RPC works)
- Injects Anthropic API key auth profile (if `ANTHROPIC_API_KEY` is set)

## Step 1: Build and Start

```bash
cd /b/docker/docker-openclaw-v3-prod
source ~/.betterai/secrets.sh  # for GITHUB_TOKEN
docker compose build
docker compose up -d openclaw
```

Wait ~30s for auto-onboard to complete, then verify:
```bash
docker logs openclaw-prod
```

You should see the startup banner with a Token value.

## Step 2: Get the Gateway Token

The gateway generates a random token during first boot. Read it from the banner:
```bash
docker logs openclaw-prod 2>&1 | grep "Token:"
```

Or read directly from the config on disk:
```bash
cat ./data/config/openclaw.json | python3 -c "import sys,json; print(json.load(sys.stdin)['gateway']['auth']['token'])"
```

**This token is the single source of truth.** Everything else must use THIS token.

## Step 3: Set the Token in Your Backend

Your backend needs to connect to the gateway using the exact same token.
Set `OPENCLAW_GATEWAY_TOKEN` in your backend's environment to the token from Step 2.

**DO NOT** change the token in openclaw.json to match the backend. Instead, always take the token FROM openclaw and give it TO the backend.

> **Why?** The gateway loads the token into memory at startup. If you edit
> the config file after the gateway is running, the running process still
> uses the OLD token. This is the #1 source of "token mismatch" errors.

If you absolutely need a specific token value, set it in the config BEFORE
first start, or restart the container after changing it:
```bash
docker restart openclaw-prod
```

## Step 4: Pair the CLI (Inside Container)

The CLI needs to be paired as a trusted device. Run this from the **host**
using `docker exec` (NOT `docker compose run`):

```bash
docker exec -u node openclaw-prod \
  node /app/openclaw.mjs devices list \
  --url ws://127.0.0.1:18789 \
  --token <TOKEN_FROM_STEP_2>
```

This connects via loopback (127.0.0.1), which **auto-approves** the CLI as
a local device. You should see "Paired (1)" in the output.

> **Why `docker exec` and not `docker compose run`?**
> `docker exec` runs inside the existing container, connecting via localhost.
> `docker compose run` creates a NEW container that connects over the Docker
> network - this is NOT localhost, so it triggers pairing instead of auto-approving.

## Step 5: Pair the Backend (External Client)

When the backend connects for the first time, it will get `pairing required`
(1008). This is expected - every non-local client must be approved.

1. **Trigger a connection** from the backend (e.g., start a proactive agent
   workflow, or restart the backend so it connects)

2. **Check pending devices:**
   ```bash
   cat ./data/config/devices/pending.json
   ```
   You'll see something like:
   ```json
   {
     "eee439f6-...": {
       "requestId": "eee439f6-...",
       "deviceId": "2f3b7b89...",
       "displayName": "backend-adapter",
       "platform": "backend",
       ...
     }
   }
   ```

3. **Approve the device** (using the requestId):
   ```bash
   docker exec -u node openclaw-prod \
     node /app/openclaw.mjs devices approve <REQUEST_ID> \
     --url ws://127.0.0.1:18789 \
     --token <TOKEN_FROM_STEP_2>
   ```

4. **Trigger reconnect** from the backend. The connection should now succeed.

> **Note:** The backend's device identity is stored in the openclaw config
> volume. As long as the volume persists, the device stays paired across
> container restarts. If you delete the volumes, you'll need to re-pair.

## Step 6: Verify Everything Works

```bash
# Check paired devices
docker exec -u node openclaw-prod \
  node /app/openclaw.mjs devices list \
  --url ws://127.0.0.1:18789 \
  --token <TOKEN_FROM_STEP_2>

# Check gateway status
docker exec -u node openclaw-prod \
  node /app/openclaw.mjs gateway status \
  --url ws://127.0.0.1:18789 \
  --token <TOKEN_FROM_STEP_2>
```

## Config Backup & Recovery

The `data/config/` directory contains tokens and device keys — it's gitignored.
The `openclaw.json.template` in the repo root preserves the full config structure
with placeholder tokens, so you can recover from scratch.

**To recover on a new server:**
```bash
mkdir -p data/config
cp openclaw.json.template data/config/openclaw.json
# Replace REPLACE_WITH_GENERATED_TOKEN with a real token, or just delete
# data/config/openclaw.json entirely and let start.sh auto-onboard from scratch
docker compose up -d openclaw
# Then follow Steps 2-5 above
```

**What's gitignored:**
- `data/config/` — openclaw.json (gateway tokens, device keys, auth profiles)
- `data/claude/` — Claude Code credentials

**What's tracked:**
- `data/workspace/` — agent workspace (Sahil's files, openclaw memory)
- `openclaw.json.template` — config structure with placeholder tokens

## Quick Reference: Common Issues

| Error | Cause | Fix |
|---|---|---|
| `token_mismatch` | Backend token != gateway's in-memory token | Read token from Step 2, update backend env, restart backend |
| `token_mismatch` after config edit | Config edited but gateway not restarted | `docker restart openclaw-prod` |
| `pairing required` (CLI) | CLI connecting over Docker network, not localhost | Use `docker exec` with `--url ws://127.0.0.1:18789` |
| `pairing required` (backend) | Backend not yet approved as trusted device | Follow Step 5 to approve |
| `Config invalid: auth.profiles` | Bad auth profile format in openclaw.json | Check `start.sh` injects `{ provider: 'anthropic', mode: 'api_key' }` |
| CLI gives "no configuration file" | Wrong entrypoint or CLI path | Use `node /app/openclaw.mjs` as the CLI command |

## Token Flow Diagram

```
First Boot:
  auto-onboard → generates random TOKEN → writes to openclaw.json
  start.sh → syncs remote.token = auth.token
  gateway process → loads TOKEN into memory

Backend:
  .env OPENCLAW_GATEWAY_TOKEN = TOKEN (copy from openclaw.json)
  backend → connects with TOKEN → gateway verifies against in-memory TOKEN

Pairing:
  localhost connection (docker exec) → auto-approved (silent=true)
  network connection (backend/CLI via docker run) → pending → manual approve
```
