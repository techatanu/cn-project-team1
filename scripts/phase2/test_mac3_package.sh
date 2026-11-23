#!/bin/bash
# Test Sambhav's package on THIS Mac (Mode 1): build dist/mac3-sambhav-backends-backupdns.zip,
# unzip it to a scratch folder and drive it ONLY through its own ./mac3.sh, exactly as Sambhav
# will, but on test ports (DNS 5301, standby edge 9443). No sudo. The firewall step is covered
# by test_extC_firewall.sh (same scripts; the zip copies are checked to be identical).
. "$(dirname "$0")/lib.sh"
start_evidence mac3-package "$@"
PKG="$SIM/pkg"; Z="$REPO/dist/mac3-sambhav-backends-backupdns.zip"
export DNS_PORT=5301 EDGE_PORT=9443 CERT_DIR
cleanup() { [ -x "$PKG/mac3-sambhav-backends-backupdns/mac3.sh" ] && "$PKG/mac3-sambhav-backends-backupdns/mac3.sh" stop >/dev/null 2>&1; }
trap cleanup EXIT

section "1. Build and inspect the zip"
"$P2_DIR/build_dist.sh"
run unzip -l "$Z"
expect "zip contains NO private key" bash -c "! unzip -l '$Z' | grep -q '\.key$'"
for f in README_SAMBHAV.md mac3.sh backend/backend.py config/mac3-backends/pf_team1.conf \
         config/mac3-backends/enable_firewall.sh config/mac3-backends/disable_firewall.sh \
         config/mac3-backup-dns/dnsmasq-backup.conf config/mac3-standby-edge/nginx-standby.conf \
         config/mac3-standby-edge/certs/app.team1.test.crt config/mac2-edge/tls/team1-ca.crt; do
  expect "zip has $f" bash -c "unzip -l '$Z' | grep -q 'mac3-sambhav-backends-backupdns/$f\$'"
done
rm -rf "$PKG"; mkdir -p "$PKG"; (cd "$PKG" && unzip -q "$Z")
M="$PKG/mac3-sambhav-backends-backupdns"; cd "$M"
expect "scripts are executable after unzip" [ -x ./mac3.sh -a -x config/mac3-backends/enable_firewall.sh ]
expect "firewall scripts in zip identical to the ones tested by Ext C" \
  diff -q config/mac3-backends/pf_team1.conf "$REPO/config/mac3-backends/pf_team1.conf"

section "2. ./mac3.sh start + status"
run ./mac3.sh start
run ./mac3.sh status
expect "backend A up"   [ "$($CURL -s -m 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:3001/)" = 200 ]
expect "backend B up"   [ "$($CURL -s -m 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:3002/)" = 200 ]
expect "backup DNS answers 10.7.16.45 with TTL 30" \
  [ "$(resolve 127.0.0.1 5301)" = "10.7.16.45" -a "$(ttl_of 127.0.0.1 5301)" = "30" ]

section "3. Ext D controls: kill-a / revive-a"
run ./mac3.sh kill-a
expect "after kill-a, :3001 is closed" bash -c "! /usr/bin/nc -z -G 1 127.0.0.1 3001"
expect "...and B still serves"   [ "$($CURL -s -m 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:3002/)" = 200 ]
run ./mac3.sh revive-a
expect "after revive-a, A serves again" [ "$($CURL -s -m 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:3001/)" = 200 ]

section "4. Ext B/E control: dns-set"
run ./mac3.sh dns-set 10.7.24.9
expect "record changed to 10.7.24.9 without restart" [ "$(resolve 127.0.0.1 5301)" = "10.7.24.9" ]
run ./mac3.sh dns-set 10.7.16.45
expect "record rolled back to 10.7.16.45" [ "$(resolve 127.0.0.1 5301)" = "10.7.16.45" ]

section "5. Ext E: standby edge"
run ./mac3.sh standby-on
expect "standby edge: 200 + X-Edge: standby" bash -c \
  "$CURL -s -D - -o /dev/null -m 5 --resolve app.team1.test:9443:127.0.0.1 --cacert '$CA' https://app.team1.test:9443/api/status | grep -qi '^x-edge: standby'"
run ./mac3.sh status

section "6. ./mac3.sh stop"
run ./mac3.sh stop
expect "everything stopped (3001, 3002, 9443 closed)" bash -c \
  "! /usr/bin/nc -z -G 1 127.0.0.1 3001 && ! /usr/bin/nc -z -G 1 127.0.0.1 3002 && ! /usr/bin/nc -z -G 1 127.0.0.1 9443"
expect "backup DNS stopped" dns_dead 127.0.0.1 5301
cd "$REPO"
summary
