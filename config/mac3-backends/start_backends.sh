#!/bin/bash
# Mac 3 - start Backend A (:3001) and/or Backend B (:3002) in the background.
#   ./start_backends.sh        both          ./start_backends.sh A     only A (Ext D revive)
# Logs: <package>/.run/backend_A.log  (watch live: tail -f ../../.run/backend_A.log)
# (Phase 1 style - two Terminal windows - also works: python3 backend/backend.py A 3001)
D="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$D/../.." && pwd)"; RUN="$ROOT/.run"
mkdir -p "$RUN"
WHICH="${1:-AB}"
for name in A B; do
  case "$WHICH" in *$name*) ;; *) continue ;; esac
  [ $name = A ] && port=3001 || port=3002
  if /usr/bin/nc -z -G 1 127.0.0.1 $port 2>/dev/null; then
    echo "Backend $name: port $port already in use (already running?)"; continue
  fi
  nohup python3 -u "$ROOT/backend/backend.py" $name $port >"$RUN/backend_$name.log" 2>&1 </dev/null &
  echo $! >"$RUN/backend_$name.pid"
  for i in 1 2 3 4 5 6 7 8 9 10; do /usr/bin/nc -z -G 1 127.0.0.1 $port 2>/dev/null && break; sleep 0.3; done
  printf 'Backend %s (pid %s): ' $name "$(cat "$RUN/backend_$name.pid")"
  /usr/bin/curl -s -m 2 http://127.0.0.1:$port/api/status || echo "NOT responding - see $RUN/backend_$name.log"
  echo
done
