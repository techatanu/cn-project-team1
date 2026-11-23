#!/bin/bash
# Mac 3 - stop backends.   ./stop_backends.sh   (both)    ./stop_backends.sh A   (Ext D: kill only A)
D="$(cd "$(dirname "$0")" && pwd)"; RUN="$(cd "$D/../.." && pwd)/.run"
WHICH="${1:-AB}"
for name in A B; do
  case "$WHICH" in *$name*) ;; *) continue ;; esac
  if [ -f "$RUN/backend_$name.pid" ] && kill "$(cat "$RUN/backend_$name.pid")" 2>/dev/null; then
    echo "Backend $name stopped"
  else
    echo "Backend $name was not started by start_backends.sh (if it runs in a Terminal window, press Ctrl+C there)"
  fi
  rm -f "$RUN/backend_$name.pid"
done
