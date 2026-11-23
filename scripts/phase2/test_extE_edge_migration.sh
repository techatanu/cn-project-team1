#!/bin/bash
# Extension E - Controlled edge migration (DNS-based cutover).
#   standby nginx (same config, X-Edge: standby) -> change the A record of app.team1.test from the
#   primary edge to the standby -> a client with a cached answer keeps hitting the OLD edge until
#   the 30 s TTL expires, a fresh lookup goes to the NEW edge at once -> then everyone is on standby.
#
# Mode 1: primary edge 127.0.0.1:8443, standby edge <en0 IP>:8443, record changed in the
#         local primary+backup dnsmasq, "client" = caching dnsmasq on :5302.
# Mode 2: MODE=lan ./test_extE_edge_migration.sh  on a client Mac (Mac 1). Standby = Mac 3.
# NOTE (Mode 1): the en0 address used here is just this Mac's second IP. On Mac 2 it happens to be
#   10.7.16.45, but in Mode 1 it is NOT playing Mac 2's LAN role (the edge is 127.0.0.1).
. "$(dirname "$0")/lib.sh"
start_evidence extE "$@"
OLD=$EDGE_IP; NEW=$ALT_IP

if [ "$MODE" = "local" ]; then
  [ -n "$NEW" ] || { echo "Need a second IP (en0). Connect to Wi-Fi and retry."; exit 1; }
  trap sim_down EXIT
  section "Setup (Mode 1): primary edge $OLD:$EDGE_PORT, standby edge $NEW:$EDGE_PORT, record -> $OLD"
  sim_up || { fail "could not start the local stack"; summary; exit 1; }
  start_nginx edge_standby "$REPO/config/mac3-standby-edge/nginx-standby.conf" "$NEW" \
    || { fail "could not start the standby edge"; summary; exit 1; }
  say "Mode 1 roles: primary edge = 127.0.0.1, standby edge = $NEW (this Mac's own Wi-Fi address standing in"
  say "for Mac 3 - it is NOT Mac 2's LAN role here)"
  client_ip()  { resolve "$CLIENT_DNS_IP" "$CLIENT_DNS_PORT"; }
  client_ttl() { ttl_of  "$CLIENT_DNS_IP" "$CLIENT_DNS_PORT"; }
  fresh_ip()   { resolve "$DNS1_IP" "$DNS1_PORT"; }
  cutover()    { set_record "$1"; hup dns_primary; hup dns_backup; sleep 0.3; }
else
  section "Mode 2 (LAN): primary edge $OLD (Mac 2) -> standby edge $NEW (Mac 3)"
  pause_lan "On Mac 3 (Sambhav): ./mac3.sh start  and  ./mac3.sh standby-on"
  client_ip()  { dscacheutil -q host -a name "$DOMAIN" | awk '/ip_address/{print $2; exit}'; }
  client_ttl() { echo "?"; }   # mDNSResponder does not show the remaining TTL
  fresh_ip()   { resolve "$MAC1_IP" 53; }
  cutover()    { lan_primary_set "$1"; }
fi

section "1. Both edges are up and identical except X-Edge"
say "primary edge $OLD: $(probe "$OLD")"
say "standby edge $NEW: $(probe "$NEW")"
expect "primary edge serves (X-Edge: primary)" [ "$(https_hdr "$OLD" X-Edge)" = "primary" ]
expect "standby edge serves (X-Edge: standby)" [ "$(https_hdr "$NEW" X-Edge)" = "standby" ]

if [ "$MODE" = "lan" ]; then
  say "the backup DNS is changed first (the client asks the primary, so this does not touch its cache)"
  lan_backup_set "$NEW"
fi
section "2. Client resolves and caches the CURRENT record"
[ "$MODE" = "lan" ] && { sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder; $CURL -s -o /dev/null https://$DOMAIN/; }
IP=$(client_ip); say "client cache: $DOMAIN -> $IP (TTL left: $(client_ttl))"
expect "client is on the primary edge ($OLD)" [ "$IP" = "$OLD" ]
say "client request: $(probe "$IP")"

section "3. CUTOVER: change the A record to the standby edge ($NEW)"
cutover "$NEW"
T0=$(date +%s)
F=$(fresh_ip); say "authoritative DNS now answers: $DOMAIN -> $F"
expect "a NEW lookup (empty cache) gets the standby edge at once" [ "$F" = "$NEW" ]
IP=$(client_ip); say "cached client still has: $IP (TTL left: $(client_ttl))"
expect "the CACHED client still gets the OLD answer (TTL not expired)" [ "$IP" = "$OLD" ]
expect "...so it still hits the OLD edge: $(https_hdr "$IP" X-Edge)" [ "$(https_hdr "$IP" X-Edge)" = "primary" ]

section "4. Watching the cached client until its TTL runs out (TTL=30 s)"
SWITCHED=""
while [ $(( $(date +%s) - T0 )) -le 60 ]; do
  [ "$MODE" = "lan" ] && $CURL -s -o /dev/null --max-time 3 https://$DOMAIN/   # keep the system resolver busy
  IP=$(client_ip)
  say "t=+$(( $(date +%s) - T0 ))s  client -> ${IP:-?}  ttl-left=$(client_ttl)  $(probe "$IP")"
  if [ "$IP" = "$NEW" ]; then SWITCHED=$(( $(date +%s) - T0 )); break; fi
  sleep 3
done
expect "client moved to the standby edge after its cache expired (t=+${SWITCHED:-never}s, TTL 30 s)" [ -n "$SWITCHED" ]
expect "client is now served by X-Edge: standby" [ "$(https_hdr "$NEW" X-Edge)" = "standby" ]

section "5. Old edge can now be drained / stopped without user impact"
if [ "$MODE" = "local" ]; then stop edge_primary; else pause_lan "On Mac 2 (Atanu): nginx -s stop   (check: pgrep nginx prints nothing)"; fi
expect "the primary edge $OLD is really down" [ "$(https_code "$OLD")" != "200" ]
IP=$(client_ip)
expect "with the primary edge stopped, the client still gets 200 (via standby $IP)" [ "$(https_code "$IP")" = "200" ]

section "6. Roll back the record to the primary edge"
if [ "$MODE" = "local" ]; then cutover "$OLD"; say "record -> $(fresh_ip)"
else pause_lan "On Mac 2 (Atanu): nginx"; lan_primary_set "$OLD"; lan_backup_set "$OLD"; say "record -> $(fresh_ip)"; fi

section "Explanation"
cat <<'EOF'
    DNS-based cutover moves NEW lookups instantly, but every resolver/client that already cached the
    old answer keeps using the old edge until its TTL expires. So: lower the TTL well before a
    migration (we use 30 s), keep the old edge running for at least one TTL (plus slack for clients
    that ignore TTL), then drain it. This is how production traffic is shifted between regions/load
    balancers with Route 53 weighted/failover records. It is NOT instant failover: for that you need
    a shared virtual IP (VRRP/keepalived) or an anycast/managed load balancer (see Ext D).
EOF
summary
