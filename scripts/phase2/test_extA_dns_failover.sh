#!/bin/bash
# Extension A - Backup DNS resolver.
#   1. primary and backup both answer app.team1.test with the same record
#   2. stop the primary -> clients keep resolving through the backup
#   3. contrast: DNS failure (no name -> no connection at all)
#      vs application failure (name resolves, TCP/TLS fine, HTTP 502)
#
# Mode 1 (default):  ./test_extA_dns_failover.sh            - fully automatic, one Mac
# Mode 2 (LAN):      MODE=lan ./test_extA_dns_failover.sh   - run on a CLIENT Mac (Mac 1 or Mac 2);
#                    it pauses and tells you what to do on Mac 1 / Mac 3.
. "$(dirname "$0")/lib.sh"
start_evidence extA "$@"

if [ "$MODE" = "local" ]; then
  trap sim_down EXIT
  section "Setup (Mode 1): backends, edge, primary DNS :$DNS1_PORT, backup DNS :$DNS2_PORT, client cache :$CLIENT_DNS_PORT"
  sim_up || { fail "could not start the local stack"; summary; exit 1; }
  say "client resolver list: primary 127.0.0.1#$DNS1_PORT, then backup 127.0.0.1#$DNS2_PORT (strict order)"

  section "1. Both DNS servers serve the same record"
  run dig +noall +answer @"$DNS1_IP" -p "$DNS1_PORT" "$DOMAIN"
  run dig +noall +answer @"$DNS2_IP" -p "$DNS2_PORT" "$DOMAIN"
  expect "primary answers $DOMAIN -> $EDGE_IP" [ "$(resolve $DNS1_IP $DNS1_PORT)" = "$EDGE_IP" ]
  expect "backup  answers $DOMAIN -> $EDGE_IP" [ "$(resolve $DNS2_IP $DNS2_PORT)" = "$EDGE_IP" ]
  IP=$(resolve $CLIENT_DNS_IP $CLIENT_DNS_PORT)
  expect "client resolves via its resolver list -> $IP" [ "$IP" = "$EDGE_IP" ]
  expect "HTTPS through the edge works (200)" [ "$(https_code "$IP")" = "200" ]
  say "client log (who answered):"; tail -n 3 "$SIM/dns_client.log" | sed 's/^/      /'

  section "2. Stop the PRIMARY DNS (like 'sudo brew services stop dnsmasq' on Mac 1)"
  stop dns_primary
  run dig +time=1 +tries=1 @"$DNS1_IP" -p "$DNS1_PORT" "$DOMAIN"
  expect "primary is down (no answer)" dns_dead "$DNS1_IP" "$DNS1_PORT"
  hup dns_client; sleep 0.3   # flush the client cache so it must ask upstream again
  say "client cache flushed (same idea as: sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder)"
  run dig +noall +answer +stats @"$CLIENT_DNS_IP" -p "$CLIENT_DNS_PORT" "$DOMAIN"
  IP=$(resolve $CLIENT_DNS_IP $CLIENT_DNS_PORT)
  expect "client STILL resolves $DOMAIN -> $IP (via backup)" [ "$IP" = "$EDGE_IP" ]
  expect "backup DNS log shows it answered the query" grep -q "query\[A\] $DOMAIN" "$SIM/dns_backup.log"
  say "backup log:"; grep "$DOMAIN" "$SIM/dns_backup.log" | tail -n 2 | sed 's/^/      /'
  expect "HTTPS still works with primary DNS down (200)" [ "$(https_code "$IP")" = "200" ]

  section "3a. APPLICATION failure: DNS fine, both backends stopped"
  start_dns dns_primary "$REPO/config/mac1-dns/dnsmasq.conf" "$DNS1_PORT"
  stop backend_A; stop backend_B
  IP=$(resolve $CLIENT_DNS_IP $CLIENT_DNS_PORT)
  expect "name still resolves -> $IP (DNS layer OK)" [ "$IP" = "$EDGE_IP" ]
  run $CURL -s -o /dev/null -w 'HTTP %{http_code}  connect=%{time_connect}s tls=%{time_appconnect}s\n' \
      --resolve "$DOMAIN:$EDGE_PORT:$IP" --cacert "$CA" "https://$DOMAIN:$EDGE_PORT/api/status"
  expect "TCP + TLS to the edge succeed but HTTP is 502 (app layer down)" [ "$(https_code "$IP")" = "502" ]

  section "3b. DNS failure: backends fine, BOTH DNS servers stopped"
  start_backend A 3001; start_backend B 3002
  stop dns_primary; stop dns_backup; hup dns_client; sleep 0.3
  run dig +time=1 +tries=1 @"$CLIENT_DNS_IP" -p "$CLIENT_DNS_PORT" "$DOMAIN"
  IP=$(resolve $CLIENT_DNS_IP $CLIENT_DNS_PORT)
  expect "name does NOT resolve (no A record returned)" [ -z "$IP" ]
  say "no IP -> the client never opens a TCP connection; curl would stop with"
  say "'curl: (6) Could not resolve host: $DOMAIN' even though the edge and backends are up:"
  say "(waiting 6 s: in 3a nginx marked both backends down for fail_timeout=5s)"; sleep 6
  expect "  ...and the edge itself is healthy (200 when reached by IP)" [ "$(https_code "$EDGE_IP")" = "200" ]

else
  section "Mode 2 (LAN). Run on a client Mac. Primary DNS $MAC1_IP, backup DNS $MAC3_IP"
  run scutil --dns
  scutil --dns | grep -qE "nameserver.*: ($MAC1_IP|127.0.0.1)$" && scutil --dns | grep -q "nameserver.*: $MAC3_IP" \
    && pass "client lists BOTH $MAC1_IP and $MAC3_IP as DNS servers" \
    || fail "client must list both: sudo networksetup -setdnsservers Wi-Fi $MAC1_IP $MAC3_IP"

  section "1. Both DNS servers serve the same record"
  run dig +noall +answer @"$MAC1_IP" "$DOMAIN"
  run dig +noall +answer @"$MAC3_IP" "$DOMAIN"
  expect "primary answers -> $MAC2_IP" [ "$(resolve $MAC1_IP 53)" = "$MAC2_IP" ]
  expect "backup answers -> $MAC2_IP"  [ "$(resolve $MAC3_IP 53)" = "$MAC2_IP" ]
  expect "HTTPS works (200)" [ "$($CURL -s -o /dev/null -w '%{http_code}' https://$DOMAIN/api/status)" = "200" ]

  pause_lan "On Mac 1 (Prince, 2nd window): ./mac1.sh dns-stop"
  section "2. Primary down -> client falls back to the backup"
  expect "primary $MAC1_IP no longer answers" dns_dead "$MAC1_IP" 53
  say "flushing this Mac's DNS cache (sudo password may be asked)"
  sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
  run dig +time=2 +tries=1 "$DOMAIN"
  run dscacheutil -q host -a name "$DOMAIN"
  dscacheutil -q host -a name "$DOMAIN" | grep -q "$MAC2_IP" \
    && pass "system resolver still returns $MAC2_IP (answered by backup $MAC3_IP)" \
    || fail "system resolver did not return $MAC2_IP"
  run $CURL -s -i --max-time 8 https://$DOMAIN/api/status
  expect "HTTPS still works with the primary DNS down" [ "$($CURL -s -o /dev/null -w '%{http_code}' --max-time 8 https://$DOMAIN/api/status)" = "200" ]

  pause_lan "On Mac 3 (Sambhav): ./mac3.sh backends-stop"
  section "3a. APPLICATION failure: name resolves, HTTP 502 or 504"
  run dig +short "$DOMAIN"
  run $CURL -s -o /dev/null -w 'HTTP %{http_code}\n' https://$DOMAIN/api/status
  pause_lan "On Mac 3 (Sambhav): ./mac3.sh backends-start   then   ./mac3.sh dns-stop"
  section "3b. DNS failure: backends up, no DNS server answers"
  sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
  run dig +time=2 +tries=1 "$DOMAIN"
  run $CURL -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 8 https://$DOMAIN/api/status
  say "expect: 'curl: (6) Could not resolve host' - no TCP connection is ever attempted"
  pause_lan "Restore: Mac 1: ./mac1.sh dns-start   AND   Mac 3: ./mac3.sh dns-start"
fi

section "Explanation"
cat <<'EOF'
    DNS failure:  the client cannot turn app.team1.test into an IP, so it never opens a TCP
                  connection. curl ends with "(6) Could not resolve host". Edge and backends may be
                  perfectly healthy. A backup resolver in the client's list removes this single point
                  of failure; the client retries the next server after a short timeout.
    App failure:  DNS answers, TCP 3-way handshake + TLS handshake with the edge succeed, but the edge
                  has no healthy backend, so nginx returns an HTTP 5xx. 502 Bad Gateway when the
                  backend host answers with RST (port closed), 504 Gateway Timeout when the SYN is
                  silently dropped (e.g. macOS firewall stealth mode) and proxy_connect_timeout (2 s)
                  expires. The fix is on the server side (restart backends / HA), not in DNS.
EOF
summary
