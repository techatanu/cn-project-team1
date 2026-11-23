#!/bin/bash
# Mac 1 (Prince) - primary DNS + test client: one entry point for every Phase 2 job.
#   ./mac1.sh start | stop          primary DNS (dnsmasq, :53, TTL 30) on / off      (sudo)
#   ./mac1.sh status                self-test: PASS/FAIL for DNS, client settings, CA, HTTPS
#   ./mac1.sh dns-stop | dns-start  Ext A: stop / start the primary DNS
#   ./mac1.sh dns-set <ip>          Ext B/E: change the A record (Mac 3 runs the same)
#   ./mac1.sh client-setup          this Mac resolves via 127.0.0.1 (itself) then 10.7.24.9 (backup)
#   ./mac1.sh client-restore        normal internet DNS again (after the project)
#   ./mac1.sh test-a|test-b|test-c|test-d|test-e   run the LAN test for that extension (client side)
#   ./mac1.sh diagnose              Ext F: DNS -> TCP -> TLS -> HTTP check, stops at the broken layer
#   ./mac1.sh fault-dns | fault-restore             Ext F practice: wrong DNS record / undo
#   ./mac1.sh collect               zip all test outputs + logs -> AirDrop it to Atanu
# Tests save to evidence/phase2/<ext>/lan_run.txt; other commands append to evidence/phase2/mac1/session_<date>.txt
# Mode 1 local test on one Mac (no sudo, port 5300):  DNS_PORT=5300 ./mac1.sh start|status|dns-set|stop
D="$(cd "$(dirname "$0")" && pwd)"
if [ -d "$D/config" ]; then ROOT="$D"; else ROOT="$(cd "$D/.." && pwd)"; fi
N="$ROOT/config/mac1-dns"; P2="$ROOT/scripts/phase2"
. "$P2/lan.env"
DNS_PORT="${DNS_PORT:-53}"; export DNS_PORT

status() {
  local ok=0 bad=0
  chk() { if eval "$2" >/dev/null 2>&1; then echo "  [PASS] $1"; ok=$((ok+1)); else echo "  [FAIL] $1"; bad=$((bad+1)); fi; }
  echo "Mac 1 self-test  ($(date '+%F %T'), DNS port $DNS_PORT)"
  echo "IP addresses: $(ifconfig | awk '/inet / && $2!="127.0.0.1"{printf "%s ", $2}')  (expected $MAC1_IP)"
  chk "Primary DNS answers app.team1.test" "dig +short +time=1 +tries=1 @127.0.0.1 -p $DNS_PORT app.team1.test | grep -qE '^[0-9.]+$'"
  chk "TTL is 30 s (Ext B)" "dig +noall +answer +time=1 +tries=1 @127.0.0.1 -p $DNS_PORT app.team1.test | awk '{print \$2}' | grep -qx 30"
  echo "        record: $(dig +noall +answer +time=1 +tries=1 @127.0.0.1 -p $DNS_PORT app.team1.test 2>/dev/null)"
  if [ "$DNS_PORT" = 53 ]; then
    chk "Backup DNS on Mac 3 ($MAC3_IP) answers the same" \
      "[ \"\$(dig +short +time=1 +tries=1 @$MAC3_IP app.team1.test)\" = \"\$(dig +short +time=1 +tries=1 @127.0.0.1 app.team1.test)\" ]"
    chk "This Mac lists BOTH DNS servers (127.0.0.1 then $MAC3_IP)" \
      "networksetup -getdnsservers Wi-Fi | tr '\n' ' ' | grep -q '127.0.0.1 $MAC3_IP'"
    chk "Team1 CA trusted in the System keychain" "security find-certificate -c 'Team1 Local CA' /Library/Keychains/System.keychain"
    chk "https://app.team1.test works (200, no -k)" "[ \"\$(/usr/bin/curl -s -o /dev/null -w '%{http_code}' -m 5 https://app.team1.test/api/status)\" = 200 ]"
  fi
  echo "Result: $ok passed, $bad failed"; [ $bad -eq 0 ]
}

main() {
case "${1:-}" in
  start|dns-start) "$N/start_primary_dns.sh" ;;
  stop|dns-stop)   "$N/stop_primary_dns.sh" ;;
  status)          status ;;
  dns-set)         "$N/set_record.sh" "${2:?usage: ./mac1.sh dns-set <ip>}" ;;
  client-setup)    sudo networksetup -setdnsservers Wi-Fi 127.0.0.1 "$MAC3_IP"
                   sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
                   echo "DNS servers: $(networksetup -getdnsservers Wi-Fi | tr '\n' ' ')" ;;
  client-restore)  sudo networksetup -setdnsservers Wi-Fi empty; echo "DNS back to the Wi-Fi default" ;;
  test-a) MODE=lan "$P2/test_extA_dns_failover.sh" ;;
  test-b) MODE=lan "$P2/test_extB_ttl_cutover.sh" ;;
  test-c) MODE=lan "$P2/test_extC_firewall.sh" ;;
  test-d) MODE=lan "$P2/test_extD_ha_failover.sh" ;;
  test-e) MODE=lan "$P2/test_extE_edge_migration.sh" ;;
  diagnose)      MODE=lan "$P2/diagnose.sh" ;;
  fault-dns)     MODE=lan "$P2/inject_fault.sh" dns-wrong-ip ;;
  fault-restore) MODE=lan "$P2/inject_fault.sh" restore ;;
  *) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
}

LOGDIR="$ROOT/evidence/phase2/mac1"; mkdir -p "$LOGDIR"
collect() {
  local TS C OUT; TS=$(date +%Y%m%d-%H%M%S); C="$LOGDIR/collected_$TS"; mkdir -p "$C"
  echo "Collecting Mac 1 results into $C ..."
  status >"$C/status.txt" 2>&1
  cp /tmp/dnsmasq.log "$C/" 2>/dev/null
  cp /opt/homebrew/etc/team1.hosts "$C/team1.hosts_now.txt" 2>/dev/null
  { networksetup -getdnsservers Wi-Fi; scutil --dns | grep nameserver | sort -u
    dscacheutil -q host -a name app.team1.test; ifconfig en0 | grep "inet "; } >"$C/client_dns_now.txt" 2>&1
  OUT="$ROOT/team1-mac1-results-$TS.zip"
  (cd "$ROOT" && zip -qr "$OUT" evidence)
  echo "Done: $OUT"
  echo ">>> AirDrop this zip to Atanu."
}
case "${1:-}" in
  ""|help|-h) main ;;
  collect)    collect ;;
  test-*)     main "$@" ;;             # tests write their own evidence file
  *) { echo; echo "##### $(date '+%F %T')  ./mac1.sh $*"; main "$@"; } 2>&1 | tee -a "$LOGDIR/session_$(date +%Y%m%d).txt"
     exit "${PIPESTATUS[0]}" ;;
esac
