#!/bin/bash
set -e

export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"

# Fix ownership on mounted volumes
chown -R node:node /home/node/.openclaw 2>/dev/null || true
chown -R node:node /home/node/.claude 2>/dev/null || true

# Auto-onboard on first run (creates openclaw.json config)
CONFIG_FILE="/home/node/.openclaw/openclaw.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "First run detected - running auto-onboard..."
    su -s /bin/bash node -c "HOME=/home/node node /app/openclaw.mjs onboard \
        --non-interactive \
        --accept-risk \
        --auth-choice skip \
        --flow quickstart \
        --gateway-bind lan \
        --gateway-port 18789 \
        --skip-channels \
        --skip-daemon \
        --skip-skills \
        --skip-ui \
        --skip-health \
        --node-manager pnpm"
    echo "Auto-onboard complete."
fi

# If ANTHROPIC_API_KEY is set, inject it into the config as an auth profile
if [ -n "$ANTHROPIC_API_KEY" ]; then
    node -e "
const fs = require('fs');
const p = '$CONFIG_FILE';
const cfg = JSON.parse(fs.readFileSync(p, 'utf8'));
cfg.auth = cfg.auth || {};
cfg.auth.profiles = cfg.auth.profiles || {};
cfg.auth.profiles['anthropic:env'] = { provider: 'anthropic', mode: 'api_key' };
fs.writeFileSync(p, JSON.stringify(cfg, null, 2));
" 2>/dev/null || true
fi

# Sync remote.token = auth.token so CLI RPC works, and read token for display
GATEWAY_TOKEN=$(node -e "
const fs = require('fs');
const p = '$CONFIG_FILE';
const cfg = JSON.parse(fs.readFileSync(p, 'utf8'));
const token = ((cfg.gateway || {}).auth || {}).token || '';
if (token) {
    cfg.gateway.remote = cfg.gateway.remote || {};
    cfg.gateway.remote.token = token;
    fs.writeFileSync(p, JSON.stringify(cfg, null, 2));
}
console.log(token || '(see config)');
" 2>/dev/null || echo "(see config)")

# Check Claude credentials
if [ -f /home/node/.claude/.credentials.json ]; then
    CLAUDE_STATUS="found"
else
    CLAUDE_STATUS="NOT FOUND - run: docker compose run --rm claude-auth"
fi

echo ""
echo "============================================"
echo "  OpenClaw + Claude Agent SDK (Prod)"
echo "============================================"
echo "  Web UI:  http://0.0.0.0:18789"
echo "  Token:   $GATEWAY_TOKEN"
echo "  Claude:  $CLAUDE_STATUS"
echo ""
echo "  CLI:  docker exec -it openclaw-prod openclaw <command>"
echo "============================================"
echo ""

# Run gateway directly as node user (no supervisor needed)
exec su -s /bin/bash node -c \
    "HOME=/home/node NODE_ENV=production NODE_COMPILE_CACHE=/home/node/.cache/node-compile \
     node /app/openclaw.mjs gateway --bind lan --port 18789"
