#!/bin/bash
# Mac 1 - stop the primary DNS.  LAN: sudo brew services stop dnsmasq.  Mode 1: DNS_PORT=5300 ./stop_primary_dns.sh
D="$(cd "$(dirname "$0")" && pwd)"; RUN="$(cd "$D/../.." && pwd)/.run"
if [ "${DNS_PORT:-53}" = 53 ]; then sudo brew services stop dnsmasq
else kill "$(cat "$RUN/dns_primary.pid" 2>/dev/null)" 2>/dev/null && echo "primary DNS stopped"; rm -f "$RUN/dns_primary.pid"; fi
