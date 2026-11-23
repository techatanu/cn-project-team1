#!/bin/bash
# Mac 3 - stop the backup DNS.  LAN: sudo brew services stop dnsmasq.  Mode 1: DNS_PORT=5301 ./stop_backup_dns.sh
D="$(cd "$(dirname "$0")" && pwd)"; RUN="$(cd "$D/../.." && pwd)/.run"
if [ "${DNS_PORT:-53}" = 53 ]; then sudo brew services stop dnsmasq
else kill "$(cat "$RUN/dns_backup.pid" 2>/dev/null)" 2>/dev/null && echo "backup DNS stopped"; rm -f "$RUN/dns_backup.pid"; fi
