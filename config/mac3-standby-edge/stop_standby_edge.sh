#!/bin/bash
# Mac 3 - stop the standby edge nginx started by start_standby_edge.sh
D="$(cd "$(dirname "$0")" && pwd)"; P="$(cd "$D/../.." && pwd)/.run/standby-edge"
if [ -f "$P/nginx.pid" ] && kill "$(cat "$P/nginx.pid")" 2>/dev/null; then echo "standby edge stopped"
else echo "standby edge was not running"; fi
