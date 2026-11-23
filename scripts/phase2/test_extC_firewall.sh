#!/bin/bash
# Extension C - Service isolation with pf (backend ports 3001/3002 reachable ONLY from the edge).
#   before: a client can bypass the edge and hit http://backend:3001 directly
#   firewall on: the edge (nginx) still reaches both backends, direct client access TIMES OUT
#   firewall off (rollback): original state restored and verified
#
# Needs sudo -> run it in Terminal.app (it asks for your password once).
# Mode 1:  ./test_extC_firewall.sh
#          backends on this Mac; "edge" = nginx connecting from 127.0.0.1; "client" = a direct
#          connection to this Mac's en0 IP (source address en0, not 127.0.0.1) -> blocked on lo0.
# Mode 2:  MODE=lan ./test_extC_firewall.sh  on Mac 1 (a client that is NOT the edge).
# NOTE (Mode 1): the en0 address used here is just this Mac's second IP. On Mac 2 it happens to be
#   10.7.16.45, but in Mode 1 it is NOT playing Mac 2's LAN role (the edge is 127.0.0.1).
. "$(dirname "$0")/lib.sh"
start_evidence extC "$@"
FW="$REPO/config/mac3-backends"
direct() { # direct <ip> <port> -> "<http_code> <curl_exit>"
  $CURL -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 "http://$1:$2/api/status"
  echo " $?"
}

if [ "$MODE" = "local" ]; then
  [ -n "$ALT_IP" ] || { echo "Need this Mac's en0 IP (connect to Wi-Fi)."; exit 1; }
  echo "sudo is needed for pfctl:"; sudo -v || exit 1
  export PF_STATE="$SIM/pf"
  FW_ON=""
  cleanup() { [ -n "$FW_ON" ] && "$FW/disable_firewall.sh" >/dev/null 2>&1; sim_down; }
  trap cleanup EXIT
  section "Setup (Mode 1): backends :3001/:3002 on 0.0.0.0, edge 127.0.0.1:$EDGE_PORT"
  sim_up || { fail "could not start the local stack"; summary; exit 1; }
  BK=$ALT_IP; EDGE_SRC=127.0.0.1
  say "Mode 1 roles: edge = nginx on 127.0.0.1; 'client' = direct connection to $ALT_IP (this Mac's own Wi-Fi address,"
  say "used only as a non-edge source address - it is NOT Mac 2's LAN role here)"
else
  BK=$MAC3_IP; EDGE_SRC=$MAC2_IP
  section "Mode 2 (LAN): this client -> backends on $BK; edge = $MAC2_IP"
fi

section "1. BEFORE: client can bypass the edge"
R=$(direct "$BK" 3001); say "direct http://$BK:3001 -> HTTP ${R% *} (curl exit ${R#* })"
expect "direct access to Backend A works (this is the problem)" [ "${R% *}" = "200" ]
expect "edge works (200)" [ "$(https_code "$( [ $MODE = local ] && echo $EDGE_IP )")" = "200" ]

section "2. Firewall ON (rollback copy saved first)"
if [ "$MODE" = "local" ]; then "$FW/enable_firewall.sh" --local && FW_ON=1
else pause_lan "On Mac 3 (Sambhav): ./mac3.sh firewall-on"; fi

section "3. Edge still reaches both backends, direct client access is blocked"
SEEN=""
for i in 1 2 3 4 5 6; do
  P=$(probe "$( [ $MODE = local ] && echo $EDGE_IP )"); say "via edge, request $i: $P"; SEEN="$SEEN $P"
done
expect "edge -> Backend A allowed (X-Backend: A seen)" bash -c "echo '$SEEN' | grep -q 'backend=A'"
expect "edge -> Backend B allowed (X-Backend: B seen)" bash -c "echo '$SEEN' | grep -q 'backend=B'"
for port in 3001 3002; do
  run $CURL -sS -m 5 --connect-timeout 3 "http://$BK:$port/api/status"
  R=$(direct "$BK" $port)
  expect "direct http://$BK:$port is BLOCKED (HTTP ${R% *}, curl exit ${R#* } = 28 timeout)" [ "${R#* }" = "28" ]
done
say "timeout (exit 28) = packets silently DROPPED by a firewall."
say "'Connection refused' (exit 7) would mean the host answered with RST = nothing listening."
[ "$MODE" = "lan" ] && say "Also show on Mac 2 (Atanu): curl -m 3 http://$BK:3001/api/status  -> 200 (edge is allowed)"

section "4. Rollback: firewall OFF, original configuration restored"
if [ "$MODE" = "local" ]; then "$FW/disable_firewall.sh" && FW_ON=""
else pause_lan "On Mac 3 (Sambhav): ./mac3.sh firewall-off"; fi
R=$(direct "$BK" 3001)
expect "after rollback direct access works again (HTTP ${R% *})" [ "${R% *}" = "200" ]
summary
