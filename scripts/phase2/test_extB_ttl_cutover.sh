#!/bin/bash
# Extension B - DNS TTL and controlled record change.
#   1. short visible TTL (local-ttl=30) on app.team1.test
#   2. client resolves -> record is changed to a different IP -> client keeps the OLD (cached)
#      answer until the TTL expires, then gets the NEW one
#   3. change it again and flush the client cache by hand -> the new answer appears immediately
#
# Mode 1: authoritative = local primary+backup dnsmasq, client cache = caching dnsmasq :5302
#         (stand-in for macOS mDNSResponder; its flush = SIGHUP, like `killall -HUP mDNSResponder`)
# Mode 2: MODE=lan ./test_extB_ttl_cutover.sh on a client Mac (Mac 1). The record is changed on
#         Mac 1 (./mac1.sh dns-set) AND Mac 3 (./mac3.sh dns-set). The client cache is
#         mDNSResponder, observed with dscacheutil (plain `dig` bypasses that cache!).
. "$(dirname "$0")/lib.sh"
start_evidence extB "$@"
OLD=$EDGE_IP
if [ "$MODE" = "local" ]; then
  NEW=10.7.24.9                                   # any different IP; nothing needs to listen there
  trap sim_down EXIT
  section "Setup (Mode 1): record $DOMAIN -> $OLD, TTL from config/mac1-dns/dnsmasq.conf"
  sim_up || { fail "could not start the local stack"; summary; exit 1; }
  client_ip()  { resolve "$CLIENT_DNS_IP" "$CLIENT_DNS_PORT"; }
  client_ttl() { ttl_of  "$CLIENT_DNS_IP" "$CLIENT_DNS_PORT"; }
  auth()       { dig +noall +answer @"$DNS1_IP" -p "$DNS1_PORT" "$DOMAIN"; }
  change()     { set_record "$1"; hup dns_primary; hup dns_backup; sleep 0.3; }
  flush()      { hup dns_client; sleep 0.3; }
  FLUSH_TXT="kill -HUP <client dnsmasq>   (Mac equivalent: sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder)"
else
  NEW=$MAC3_IP
  section "Mode 2 (LAN): record $DOMAIN -> $OLD; client cache = mDNSResponder on this Mac"
  client_ip()  { dscacheutil -q host -a name "$DOMAIN" | awk '/ip_address/{print $2; exit}'; }
  client_ttl() { echo "n/a"; }
  auth()       { dig +noall +answer @"$MAC1_IP" "$DOMAIN"; }
  change()     { lan_primary_set "$1"; }
  flush()      { sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder; sleep 1; }
  FLUSH_TXT="sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"
  flush
fi

section "1. Short, visible TTL"
run auth
TTL=$( [ "$MODE" = local ] && ttl_of "$DNS1_IP" "$DNS1_PORT" || ttl_of "$MAC1_IP" 53 )
expect "authoritative answer carries TTL 30 (local-ttl=30)" [ "$TTL" = "30" ]

if [ "$MODE" = "lan" ]; then
  say "the backup DNS is changed first (the client asks the primary, so this does not touch its cache)"
  lan_backup_set "$NEW"; sudo -v
fi
section "2. Client resolves and caches $DOMAIN"
IP=$(client_ip); say "client: $DOMAIN -> $IP  (TTL left: $(client_ttl))"
expect "client has the current record $OLD" [ "$IP" = "$OLD" ]

section "3. Change the record to a different IP ($NEW)"
change "$NEW"; T0=$(date +%s)
run auth
expect "DNS server now answers $NEW" [ "$( [ "$MODE" = local ] && resolve "$DNS1_IP" "$DNS1_PORT" || resolve "$MAC1_IP" 53 )" = "$NEW" ]

section "4. Client keeps the cached OLD answer until the TTL expires"
SEEN_OLD=0; SWITCHED=""
while [ $(( $(date +%s) - T0 )) -le 60 ]; do
  IP=$(client_ip); t=$(( $(date +%s) - T0 ))
  say "t=+${t}s  client -> $IP   ttl-left=$(client_ttl)"
  [ "$IP" = "$OLD" ] && SEEN_OLD=1
  if [ "$IP" = "$NEW" ]; then SWITCHED=$t; break; fi
  sleep 3
done
expect "client served the OLD (cached) answer after the change" [ "$SEEN_OLD" = 1 ]
# Mode 1 (dnsmasq cache) switches at ~30-31 s. The macOS system cache (mDNSResponder) was measured
# switching at +36..40 s on the LAN (23 Nov, run 2), so in LAN mode we allow TTL + 15 s.
LIMIT=35; [ "$MODE" = "lan" ] && LIMIT=45
expect "client switched to the NEW answer once the TTL expired (t=+${SWITCHED:-never}s, TTL 30 s, limit ${LIMIT}s)" \
  [ "${SWITCHED:-99}" -le "$LIMIT" ]

section "5. Manual flush: change back to $OLD and flush the client cache"
change "$OLD"
IP=$(client_ip); say "right after the change, client still says: $IP (cached)"
expect "without a flush the client still has the cached $NEW" [ "$IP" = "$NEW" ]
say "flush: $FLUSH_TXT"; flush
IP=$(client_ip); say "right after the flush, client says: $IP"
expect "after the manual flush the new answer ($OLD) appears IMMEDIATELY" [ "$IP" = "$OLD" ]
[ "$MODE" = "lan" ] && lan_backup_set "$OLD"

section "Explanation"
cat <<'EOF'
    The TTL is a promise from the DNS server: "you may reuse this answer for 30 s". Resolvers and
    clients cache it and do not ask again until it expires, so a record change reaches each client
    up to one TTL later. Flushing the cache forces a fresh lookup at once, but only on that machine.
    Production cutover (Route 53, region/LB migration): lower the TTL a day ahead (one OLD TTL),
    change the record, keep the old target running for at least one TTL, then retire it. Short TTL
    = faster cutover but more DNS queries; long TTL = fewer queries but slow, uneven migration.
EOF
summary
