#!/bin/bash
# Deploy warp-watchdog to this server

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cp "$SCRIPT_DIR/warp-watchdog.sh" /root/warp-watchdog.sh
chmod +x /root/warp-watchdog.sh

# Kill old watchdog if running
if command -v screen &>/dev/null; then
    screen -S watchdog -X quit 2>/dev/null
    screen -dmS watchdog bash /root/warp-watchdog.sh
    echo "Watchdog started in screen session 'watchdog'"
else
    nohup bash /root/warp-watchdog.sh &
    echo "Watchdog started in background (PID $!)"
fi
