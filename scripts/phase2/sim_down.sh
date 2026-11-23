#!/bin/bash
# Mode 1: stop the stack started by sim_up.sh (clears any injected fault first).
# Refuses to touch a stack that belongs to a test that is still running.
. "$(dirname "$0")/lib.sh"
owner="$(cat "$SIM/lock/pid" 2>/dev/null)"
if [ -n "$owner" ] && [ "$owner" != persistent ] && kill -0 "$owner" 2>/dev/null; then
  echo "A test (pid $owner) owns the running stack - not stopping it. Wait for the test to finish."; exit 1
fi
[ -f "$SIM/fault" ] && "$P2_DIR/inject_fault.sh" restore
_kill_all; rm -rf "$SIM/lock"; echo "team1 stack stopped."
