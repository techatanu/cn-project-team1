#!/bin/bash
# Extension D - High-availability failover.
#   continuous HTTPS traffic through the edge -> stop Backend A -> 0 failed requests, all served by B
#   -> restart Backend A -> round-robin over A and B resumes.
# nginx settings under test (config/mac2-edge/nginx/team1-phase2.conf):
#   max_fails=1 fail_timeout=5s, proxy_connect_timeout 2s,
#   proxy_next_upstream error timeout http_502 http_503
#
# Mode 1:  ./test_extD_ha_failover.sh
# Mode 2:  MODE=lan ./test_extD_ha_failover.sh   (on a client Mac; Sambhav runs ./mac3.sh kill-a / revive-a)
. "$(dirname "$0")/lib.sh"
start_evidence extD "$@"
TRAFFIC_IP=""; [ "$MODE" = "local" ] && TRAFFIC_IP=$EDGE_IP
T="$SIM/traffic.txt"; STOPF="$SIM/traffic.stop"

traffic() { # one request every 0.2 s until $STOPF exists; lines: "<n> <time> <code> backend=X edge=Y"
  local n=0
  while [ ! -e "$STOPF" ]; do
    n=$((n+1)); echo "$n $(date +%T) $(probe "$TRAFFIC_IP")" >>"$T"; sleep 0.2
  done
}
lines() { wc -l <"$T" | tr -d ' '; }
wait_lines() { while [ "$(lines)" -lt "$1" ]; do sleep 0.2; done; }

if [ "$MODE" = "local" ]; then
  trap 'touch "$STOPF"; sim_down' EXIT
  section "Setup (Mode 1): backends A :3001 + B :3002, edge 127.0.0.1:$EDGE_PORT"
  sim_up || { fail "could not start the local stack"; summary; exit 1; }
else
  mkdir -p "$SIM"
  section "Mode 2 (LAN): traffic to https://$DOMAIN (edge $MAC2_IP, backends on $MAC3_IP)"
fi
rm -f "$T" "$STOPF"; : >"$T"

section "1. Baseline: round-robin over both backends"
for i in 1 2 3 4 5 6; do say "request $i: $(probe "$TRAFFIC_IP")"; done

section "2. Continuous traffic (5 req/s), then stop Backend A"
traffic & TPID=$!
wait_lines 10
if [ "$MODE" = "local" ]; then stop backend_A; else pause_lan "On Mac 3 (Sambhav): ./mac3.sh kill-a   (or Ctrl+C in the Backend A window)"; fi
KILL_AT=$(lines); say ">>> Backend A STOPPED after request $KILL_AT"
wait_lines $((KILL_AT + 40))
REVIVE_AT=$(lines)   # counted BEFORE the revive: the window KILL_AT..REVIVE_AT is inside the real outage
if [ "$MODE" = "local" ]; then start_backend A 3001; else pause_lan "On Mac 3: ./mac3.sh revive-a"; fi
say ">>> Backend A RESTARTED after request $(lines) (outage window counted: requests $((KILL_AT+1))-$REVIVE_AT)"
say "waiting 7 s (fail_timeout=5s: nginx retries A only after the 5 s penalty)"
sleep 7
END_AT=$(lines); wait_lines $((END_AT + 15)); touch "$STOPF"; wait $TPID 2>/dev/null
say "traffic log ($(lines) requests):"; sed 's/^/      /' "$T"

TOTAL=$(lines)
FAILED=$(awk '$3!="200"' "$T" | wc -l | tr -d ' ')
DOWN=$(awk -v a="$KILL_AT" -v b="$REVIVE_AT" '$1>a && $1<=b' "$T")
DOWN_N=$(echo "$DOWN" | grep -c .)
DOWN_B=$(echo "$DOWN" | grep -c 'backend=B')
AFTER=$(awk -v e="$END_AT" '$1>e' "$T")

section "Results"
say "total requests: $TOTAL   failed (non-200): $FAILED"
say "while A was down: $DOWN_N requests, $DOWN_B served by B"
expect "0 failed requests during the whole test" [ "$FAILED" -eq 0 ]
expect "while A was down, 100% of requests were served by Backend B" [ "$DOWN_N" -gt 0 -a "$DOWN_N" -eq "$DOWN_B" ]
expect "after A came back, round-robin uses A again"  bash -c "echo \"$AFTER\" | grep -q 'backend=A'"
expect "after A came back, B still serves too"        bash -c "echo \"$AFTER\" | grep -q 'backend=B'"

if [ "$MODE" = "local" ]; then
  section "nginx access log: the request that hit dead A and was retried on B"
  grep -m 3 ', 127.0.0.1:300' "$SIM/edge_primary/access.log" | sed 's/^/      /'
  grep -q 'up_status=502, 200\|, 127.0.0.1:3002.*200' "$SIM/edge_primary/access.log" \
    && say "(\$upstream_addr lists A then B: first attempt failed, retried on B, client got 200)"
else
  say "On Mac 2: grep ', 10.7.24.9' /opt/homebrew/var/log/nginx/team1_access.log   (retried requests)"
fi

section "Single point of failure (Ext D question)"
cat <<'EOF'
    Backends are now redundant, but the EDGE (nginx on Mac 2) is still a single point of failure:
    app.team1.test resolves only to 10.7.16.45; if Mac 2 or its nginx dies, every request fails
    even though both backends are healthy. Mac 3 is a second SPOF in our 3-laptop design: it hosts
    BOTH backends (and the backup DNS and the standby edge), so losing the laptop loses everything.
    To remove the edge SPOF in production:
      * Two edge nodes + VRRP (keepalived): both share one virtual IP; the backup takes the VIP
        within ~1-3 s when the master stops sending VRRP adverts. DNS never changes.
      * DNS round-robin / health-checked DNS (Route 53 failover records): publish both edge IPs
        with a short TTL; clients retry the other IP. Slower (bounded by TTL + client caches).
      * Managed cloud LB (AWS ALB, GCP LB): the provider runs the redundant edge fleet for you.
    Ext E shows the manual, DNS-based version of this: moving traffic to a standby edge.
EOF
summary
