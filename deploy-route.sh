#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REMOTE="${REMOTE:-root@107.173.146.101}"
REMOTE_DIR="${REMOTE_DIR:-/root/tz_router_opt}"
CONFIG_PATH="${CONFIG_PATH:-/etc/s-box/sb.json}"

ssh "$REMOTE" "mkdir -p '$REMOTE_DIR'"
scp "$SCRIPT_DIR/warp-allowlist.txt" "$REMOTE:$REMOTE_DIR/warp-allowlist.txt"
scp "$SCRIPT_DIR/sync-singbox-route.py" "$REMOTE:$REMOTE_DIR/sync-singbox-route.py"

ssh "$REMOTE" "set -e
  ts=\$(date +%Y%m%d-%H%M%S)
  cp '$CONFIG_PATH' '$CONFIG_PATH.bak-warp-allowlist-'\$ts
  python3 '$REMOTE_DIR/sync-singbox-route.py' \
    --config '$CONFIG_PATH' \
    --allowlist '$REMOTE_DIR/warp-allowlist.txt' \
    --warp-tag warp-out \
    --default-interface eth0
  ENABLE_DEPRECATED_LEGACY_DOMAIN_STRATEGY_OPTIONS=true /etc/s-box/sing-box check -c '$CONFIG_PATH'
  systemctl reload sing-box || systemctl restart sing-box
  systemctl is-active sing-box
  echo backup='$CONFIG_PATH.bak-warp-allowlist-'\$ts
"
