#!/bin/bash
# Mac 3 (Sambhav) - one entry point for every Phase 2 job on this Mac.
#   ./mac3.sh start            start Backend A (:3001) + Backend B (:3002) + backup DNS (:53)
#   ./mac3.sh stop             stop all of it (backends, backup DNS, standby edge) + firewall off
#   ./mac3.sh status           self-test: PASS/FAIL for every Mac 3 service
#   ./mac3.sh kill-a | revive-a           Ext D: stop / restart Backend A only
#   ./mac3.sh backends-stop | backends-start   Ext A: both backends down / up (app failure demo)
#   ./mac3.sh dns-stop | dns-start        Ext A: stop / start the backup DNS
#   ./mac3.sh firewall-on | firewall-off  Ext C: pf rules on / rollback   (sudo)
#   ./mac3.sh standby-on | standby-off    Ext E: standby edge nginx on :443
#   ./mac3.sh dns-set <ip>                Ext B/E: change the A record on the backup DNS
#   ./mac3.sh collect                     zip all logs + evidence -> AirDrop it to Atanu
# Every command's output is also appended to evidence/phase2/mac3/session_<date>.txt
# Mode 1 local test on a single Mac (no sudo, other ports):
#   DNS_PORT=5301 EDGE_PORT=9443 ./mac3.sh start|status|...   (firewall: add --local)
D="$(cd "$(dirname "$0")" && pwd)"
if [ -d "$D/config" ]; then ROOT="$D"; else ROOT="$(cd "$D/.." && pwd)"; fi
B="$ROOT/config/mac3-backends"; N="$ROOT/config/mac3-backup-dns"; S="$ROOT/config/mac3-standby-edge"
CA="$ROOT/config/mac2-edge/tls/team1-ca.crt"
DNS_PORT="${DNS_PORT:-53}"; EDGE_PORT="${EDGE_PORT:-443}"; export DNS_PORT EDGE_PORT

status() {
  local ok=0 bad=0
  chk() { if eval "$2" >/dev/null 2>&1; then echo "  [PASS] $1"; ok=$((ok+1)); else echo "  [FAIL] $1"; bad=$((bad+1)); fi; }
  echo "Mac 3 self-test  ($(date '+%F %T'), DNS port $DNS_PORT, edge port $EDGE_PORT)"
  echo "IP addresses: $(ifconfig | awk '/inet / && $2!="127.0.0.1"{printf "%s ", $2}')"
  chk "Backend A answers on :3001 with X-Backend: A" "/usr/bin/curl -s -i -m 2 http://127.0.0.1:3001/api/status | grep -qi '^x-backend: A'"
  chk "Backend B answers on :3002 with X-Backend: B" "/usr/bin/curl -s -i -m 2 http://127.0.0.1:3002/api/status | grep -qi '^x-backend: B'"
  chk "Backends listen on ALL interfaces (not only 127.0.0.1)" "lsof -nP -iTCP:3001 -sTCP:LISTEN | grep -q '\*:3001'"
  chk "Backup DNS answers app.team1.test" "dig +short +time=1 +tries=1 @127.0.0.1 -p $DNS_PORT app.team1.test | grep -qE '^[0-9.]+$'"
  echo "        record: $(dig +noall +answer +time=1 +tries=1 @127.0.0.1 -p $DNS_PORT app.team1.test 2>/dev/null)"
  if /usr/bin/nc -z -G 1 127.0.0.1 "$EDGE_PORT" 2>/dev/null; then
    chk "Standby edge on :$EDGE_PORT returns 200 with X-Edge: standby" \
      "/usr/bin/curl -s -D - -o /dev/null -m 5 --resolve app.team1.test:$EDGE_PORT:127.0.0.1 --cacert '$CA' https://app.team1.test:$EDGE_PORT/api/status | grep -qi '^x-edge: standby'"
  else
    echo "  [ -- ] standby edge not running (only needed for Ext E: ./mac3.sh standby-on)"
  fi
  if sudo -n true 2>/dev/null; then
    R=$(sudo pfctl -a com.apple/team1 -sr 2>/dev/null)
    [ -n "$R" ] && echo "  [ ON ] firewall rules loaded:" && echo "$R" | sed 's/^/          /' || echo "  [OFF ] firewall (Ext C) not active"
  else
    echo "  [ ?? ] firewall state needs sudo: sudo pfctl -a com.apple/team1 -sr"
  fi
  echo "Result: $ok passed, $bad failed"
  [ $bad -eq 0 ]
}

FW_ARG=""; [ "${2:-}" = "--local" ] && FW_ARG="--local"
main() {
case "${1:-}" in
  start)        "$B/start_backends.sh"; "$N/start_backup_dns.sh" ;;
  stop)         "$S/stop_standby_edge.sh"; "$B/stop_backends.sh"; "$N/stop_backup_dns.sh"
                [ "$DNS_PORT" = 53 ] && "$B/disable_firewall.sh" ;;
  status)       status ;;
  kill-a)       "$B/stop_backends.sh" A ;;
  revive-a)     "$B/start_backends.sh" A ;;
  backends-stop)  "$B/stop_backends.sh" ;;
  backends-start) "$B/start_backends.sh" ;;
  dns-stop)     "$N/stop_backup_dns.sh" ;;
  dns-start)    "$N/start_backup_dns.sh" ;;
  dns-set)      "$N/set_record.sh" "${2:?usage: ./mac3.sh dns-set <ip>}" ;;
  firewall-on)  "$B/enable_firewall.sh" $FW_ARG ;;
  firewall-off) "$B/disable_firewall.sh" ;;
  standby-on)   "$S/start_standby_edge.sh" ;;
  standby-off)  "$S/stop_standby_edge.sh" ;;
  *) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
}

LOGDIR="$ROOT/evidence/phase2/mac3"; mkdir -p "$LOGDIR"
collect() {
  local TS C OUT; TS=$(date +%Y%m%d-%H%M%S); C="$LOGDIR/collected_$TS"; mkdir -p "$C"
  echo "Collecting Mac 3 results into $C ..."
  status >"$C/status.txt" 2>&1
  cp "$ROOT"/.run/*.log "$C/" 2>/dev/null
  cp "$ROOT/.run/standby-edge/access.log" "$C/standby_edge_access.log" 2>/dev/null
  cp "$ROOT/.run/standby-edge/error.log"  "$C/standby_edge_error.log" 2>/dev/null
  cp /tmp/dnsmasq-backup.log "$C/" 2>/dev/null
  cp /opt/homebrew/etc/team1.hosts "$C/team1.hosts_now.txt" 2>/dev/null
  cp -R "$HOME/team1-pf-backup" "$C/pf-backup" 2>/dev/null
  { echo "# pf anchor com.apple/team1 now:"; sudo pfctl -a com.apple/team1 -sr 2>/dev/null
    echo "# pf status:"; sudo pfctl -s info 2>/dev/null | head -1; } >"$C/pf_now.txt"
  { ifconfig en0 | grep "inet "; lsof -nP -iTCP -sTCP:LISTEN | grep -E ':(3001|3002|443|53) '; } >"$C/network_now.txt" 2>&1
  OUT="$ROOT/team1-mac3-results-$TS.zip"
  (cd "$ROOT" && zip -qr "$OUT" evidence)
  echo "Done: $OUT"
  echo ">>> AirDrop this zip to Atanu."
}
case "${1:-}" in
  ""|help|-h) main ;;
  collect)    collect ;;
  *) { echo; echo "##### $(date '+%F %T')  ./mac3.sh $*"; main "$@"; } 2>&1 | tee -a "$LOGDIR/session_$(date +%Y%m%d).txt"
     exit "${PIPESTATUS[0]}" ;;
esac
