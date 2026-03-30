#!/usr/bin/env bash
set -euo pipefail

# tailscale-runner.sh — Join the OCD tailnet as an ephemeral runner node.
#
# Uses Tailscale OAuth client credentials to generate a fresh ephemeral
# auth key, then joins the tailnet with tag:runner. The node auto-removes
# when the runner shuts down.
#
# Required env vars:
#   TS_OAUTH_CLIENT_ID     — Tailscale OAuth client ID
#   TS_OAUTH_CLIENT_SECRET — Tailscale OAuth client secret
#
# Optional:
#   TS_TAILNET     — tailnet name (default: auto-detect from OAuth)
#   TS_HOSTNAME    — node hostname (default: runner-<random>)
#   TS_EXTRA_ARGS  — additional args to pass to tailscale up

: "${TS_OAUTH_CLIENT_ID:?TS_OAUTH_CLIENT_ID is required}"
: "${TS_OAUTH_CLIENT_SECRET:?TS_OAUTH_CLIENT_SECRET is required}"

TS_HOSTNAME="${TS_HOSTNAME:-runner-$(head -c 4 /dev/urandom | xxd -p)}"
TS_EXTRA_ARGS="${TS_EXTRA_ARGS:-}"

echo "==> Generating ephemeral auth key via OAuth..."

# Get an OAuth access token
ACCESS_TOKEN=$(curl -s -X POST "https://api.tailscale.com/api/v2/oauth/token" \
  -u "${TS_OAUTH_CLIENT_ID}:${TS_OAUTH_CLIENT_SECRET}" \
  -d "grant_type=client_credentials" \
  | jq -r '.access_token')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
  echo "ERROR: Failed to get OAuth access token" >&2
  exit 1
fi

# Generate an ephemeral, reusable auth key tagged as runner
TS_TAILNET="${TS_TAILNET:-"-"}"
AUTH_KEY=$(curl -s -X POST "https://api.tailscale.com/api/v2/tailnet/${TS_TAILNET}/keys" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "capabilities": {
      "devices": {
        "create": {
          "reusable": false,
          "ephemeral": true,
          "preauthorized": true,
          "tags": ["tag:runner"]
        }
      }
    },
    "expirySeconds": 3600
  }' \
  | jq -r '.key')

if [ -z "$AUTH_KEY" ] || [ "$AUTH_KEY" = "null" ]; then
  echo "ERROR: Failed to generate auth key" >&2
  exit 1
fi

echo "==> Joining tailnet as ${TS_HOSTNAME} (tag:runner, ephemeral)..."

# Start tailscaled if not running
if ! pgrep -x tailscaled > /dev/null 2>&1; then
  sudo tailscaled --state=mem: &
  sleep 2
fi

# Join the tailnet
sudo tailscale up \
  --authkey="${AUTH_KEY}" \
  --hostname="${TS_HOSTNAME}" \
  --advertise-tags=tag:runner \
  ${TS_EXTRA_ARGS}

echo "==> Connected to tailnet as ${TS_HOSTNAME}"
tailscale status --peers=false
