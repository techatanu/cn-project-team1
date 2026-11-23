#!/bin/bash
# Change the team1.test A record on THIS DNS server (Ext B TTL test / Ext E edge cutover).
# Run the SAME command on Mac 1 (primary) and Mac 3 (backup) so both give the same answer.
#   ./set_record.sh 10.7.24.9     -> app/api.team1.test now point to the standby edge (Mac 3)
#   ./set_record.sh 10.7.16.45     -> back to the primary edge (Mac 2)
# dnsmasq re-reads the hosts file on SIGHUP: no restart, its cache is cleared.
# (identical copies: config/mac1-dns/set_record.sh and config/mac3-backup-dns/set_record.sh)
D="$(cd "$(dirname "$0")" && pwd)"; RUN="$(cd "$D/../.." && pwd)/.run"
IP="${1:?usage: $0 <new-ip>}"
PORT="${DNS_PORT:-53}"
if [ "$PORT" = 53 ]; then HOSTS=/opt/homebrew/etc/team1.hosts; else HOSTS="$RUN/team1.hosts"; fi
printf '# changed %s by set_record.sh\n%s app.team1.test api.team1.test\n' "$(date '+%F %T')" "$IP" >"$HOSTS"
if [ "$PORT" = 53 ]; then sudo killall -HUP dnsmasq
else for n in dns_primary dns_backup; do [ -f "$RUN/$n.pid" ] && kill -HUP "$(cat "$RUN/$n.pid")"; done; fi
sleep 0.5
echo "record now:"; dig +noall +answer @127.0.0.1 -p "$PORT" app.team1.test | sed 's/^/  /'
