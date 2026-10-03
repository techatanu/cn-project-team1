#!/bin/bash
# Load-balancing check: prints X-Backend for N requests (default 6).  Usage: ./lb_test.sh [N]
# On Mac 3 this uses /usr/bin/curl because Anaconda's curl ignores the macOS Keychain.
N=${1:-6}
for i in $(seq 1 "$N"); do
  printf "request %s: " "$i"
  /usr/bin/curl -s -i https://app.team1.test/api/status | grep -i '^x-backend' || echo "(no X-Backend header)"
done
