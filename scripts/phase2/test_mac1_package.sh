#!/bin/bash
# Test Prince's package on THIS Mac (Mode 1): build dist/mac1-prince-dns.zip, unzip it and
# drive it only through its own ./mac1.sh on test port 5300 (no sudo).
. "$(dirname "$0")/lib.sh"
start_evidence mac1-package "$@"
PKG="$SIM/pkg1"; Z="$REPO/dist/mac1-prince-dns.zip"; M="$PKG/mac1-prince-dns"
export DNS_PORT=5300
cleanup() { [ -x "$M/mac1.sh" ] && "$M/mac1.sh" stop >/dev/null 2>&1; }
trap cleanup EXIT

section "1. Build and inspect the zip"
"$P2_DIR/build_dist.sh" | grep mac1
run unzip -l "$Z"
expect "zip contains NO private key" bash -c "! unzip -l '$Z' | grep -q '\.key$'"
for f in README_PRINCE.md mac1.sh config/mac1-dns/dnsmasq.conf config/mac1-dns/team1.hosts \
         config/mac1-dns/start_primary_dns.sh config/mac1-dns/set_record.sh config/mac2-edge/tls/team1-ca.crt \
         scripts/phase2/lib.sh scripts/phase2/lan.env scripts/phase2/test_extA_dns_failover.sh \
         scripts/phase2/test_extB_ttl_cutover.sh scripts/phase2/test_extC_firewall.sh \
         scripts/phase2/test_extD_ha_failover.sh scripts/phase2/test_extE_edge_migration.sh \
         scripts/phase2/diagnose.sh scripts/phase2/inject_fault.sh; do
  expect "zip has $f" bash -c "unzip -l '$Z' | grep -q 'mac1-prince-dns/$f\$'"
done
expect "set_record.sh identical on Mac 1 and Mac 3" \
  diff -q "$REPO/config/mac1-dns/set_record.sh" "$REPO/config/mac3-backup-dns/set_record.sh"
rm -rf "$PKG"; mkdir -p "$PKG"; (cd "$PKG" && unzip -q "$Z"); cd "$M"
expect "scripts executable after unzip" [ -x ./mac1.sh -a -x scripts/phase2/test_extB_ttl_cutover.sh ]
run ./mac1.sh
expect "help lists the commands" bash -c "./mac1.sh 2>/dev/null | grep -q 'test-a'"

section "2. ./mac1.sh start + status (test port 5300)"
run ./mac1.sh start
run ./mac1.sh status
expect "primary DNS answers 10.7.16.45" [ "$(resolve 127.0.0.1 5300)" = "10.7.16.45" ]
expect "TTL is 30" [ "$(ttl_of 127.0.0.1 5300)" = "30" ]

section "3. ./mac1.sh dns-set (Ext B / E)"
run ./mac1.sh dns-set 10.7.24.9
expect "record changed to 10.7.24.9 without restart" [ "$(resolve 127.0.0.1 5300)" = "10.7.24.9" ]
run ./mac1.sh dns-set 10.7.16.45
expect "record rolled back" [ "$(resolve 127.0.0.1 5300)" = "10.7.16.45" ]

section "4. LAN test scripts inside the zip load cleanly"
for t in scripts/phase2/test_ext*.sh scripts/phase2/diagnose.sh scripts/phase2/inject_fault.sh; do
  expect "bash -n $t" bash -n "$t"
done
expect "LAN mode picks the real IPs (edge 10.7.16.45:443, DNS 10.7.23.243 + 10.7.24.9)" bash -c \
  "MODE=lan; . scripts/phase2/lib.sh; [ \$EDGE_IP = 10.7.16.45 -a \$EDGE_PORT = 443 -a \$DNS1_IP = 10.7.23.243 -a \$DNS2_IP = 10.7.24.9 ]"

section "5. ./mac1.sh stop"
run ./mac1.sh stop
expect "primary DNS stopped" dns_dead 127.0.0.1 5300
cd "$REPO"
summary
