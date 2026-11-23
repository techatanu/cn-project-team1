#!/bin/bash
# Mac 3 - start the BACKUP DNS (dnsmasq) for team1.test.  Ext A.
#   LAN:     ./start_backup_dns.sh              installs config to /opt/homebrew/etc, port 53, needs sudo
#   Mode 1:  DNS_PORT=5301 ./start_backup_dns.sh   same config on 127.0.0.1:5301, no sudo (local test)
D="$(cd "$(dirname "$0")" && pwd)"; RUN="$(cd "$D/../.." && pwd)/.run"; mkdir -p "$RUN"
DNSMASQ="$(command -v dnsmasq || echo /opt/homebrew/sbin/dnsmasq)"
[ -x "$DNSMASQ" ] || { echo "dnsmasq is not installed: brew install dnsmasq"; exit 1; }
PORT="${DNS_PORT:-53}"
if [ "$PORT" = 53 ]; then
  ETC=/opt/homebrew/etc
  if [ -f $ETC/dnsmasq.conf ] && ! cmp -s $ETC/dnsmasq.conf "$D/dnsmasq-backup.conf"; then
    cp $ETC/dnsmasq.conf "$ETC/dnsmasq.conf.before-team1-$(date +%Y%m%d-%H%M%S)"
    echo "Backed up the old $ETC/dnsmasq.conf"
  fi
  cp "$D/dnsmasq-backup.conf" $ETC/dnsmasq.conf
  cp "$D/team1.hosts" $ETC/team1.hosts
  # listen on this Mac's real Wi-Fi device (not always en0)
  WIFI=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2; exit}')
  [ -n "$WIFI" ] && sed -i '' "s/^interface=.*/interface=$WIFI/" $ETC/dnsmasq.conf && echo "Listening on Wi-Fi device $WIFI"
  # allow incoming DNS through the macOS Application Firewall (harmless if it is off)
  REAL=$(realpath "$DNSMASQ" 2>/dev/null || echo "$DNSMASQ")
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add "$REAL" >/dev/null 2>&1
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "$REAL" >/dev/null 2>&1
  "$DNSMASQ" --test -C $ETC/dnsmasq.conf || exit 1
  sudo brew services restart dnsmasq
  sleep 1
else
  # local test: derive a loopback-only config from the real file
  sed -E '/^(interface|listen-address|addn-hosts|log-facility|server)=/d' "$D/dnsmasq-backup.conf" >"$RUN/dns_backup.conf"
  cp "$D/team1.hosts" "$RUN/team1.hosts"
  printf 'port=%s\nlisten-address=127.0.0.1\nbind-interfaces\nno-hosts\naddn-hosts=%s\nlog-facility=%s\npid-file=\n' \
    "$PORT" "$RUN/team1.hosts" "$RUN/dns_backup.log" >>"$RUN/dns_backup.conf"
  nohup "$DNSMASQ" --keep-in-foreground -C "$RUN/dns_backup.conf" >"$RUN/dns_backup.out" 2>&1 </dev/null &
  echo $! >"$RUN/dns_backup.pid"
  sleep 1
fi
echo "dig @127.0.0.1 -p $PORT app.team1.test:"
dig +noall +answer @127.0.0.1 -p "$PORT" app.team1.test api.team1.test | sed 's/^/  /'
