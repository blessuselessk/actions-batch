#!/bin/bash
# tailscale-mesh.sh — example batch job that uses the tailnet mesh
#
# This job joins the OCD tailnet, discovers peer runners,
# and demonstrates inter-runner communication.
#
# Requires secrets: TS_OAUTH_CLIENT_ID, TS_OAUTH_CLIENT_SECRET

set -euo pipefail

echo "==> Tailscale status"
tailscale status

echo ""
echo "==> Finding peer runners on the mesh..."
PEERS=$(tailscale status --json | jq -r '.Peer[] | select(.Tags // [] | any(. == "tag:runner")) | .HostName')

if [ -z "$PEERS" ]; then
  echo "No peer runners found (I might be the only one)"
else
  echo "Peer runners:"
  echo "$PEERS" | while read -r peer; do
    echo "  - ${peer}"
  done

  echo ""
  echo "==> Pinging first peer..."
  FIRST_PEER=$(echo "$PEERS" | head -1)
  tailscale ping "${FIRST_PEER}" --timeout 5s || echo "Ping timed out (peer may not be ready yet)"
fi

echo ""
echo "==> Reaching gateway..."
tailscale ping fogell --timeout 5s || echo "Gateway not reachable"

echo ""
echo "==> Done. Runner mesh is operational."
