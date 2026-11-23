#!/bin/bash
# Mac 3 - start the STANDBY EDGE (nginx, TLS, load balancer) for Ext E.
# Runs a private nginx instance (own prefix in <package>/.run/standby-edge); Homebrew's
# nginx.conf and any other nginx on this Mac are not touched.
#   LAN:     ./start_standby_edge.sh                 listens on :443 (all interfaces)
#   Mode 1:  EDGE_PORT=9443 ./start_standby_edge.sh  local test on another port
# Needs the TLS key: AirDrop app.team1.test.key from Atanu (Mac 2) into ./certs/
# (the certificate app.team1.test.crt is already there). The key is never put in git/zip.
D="$(cd "$(dirname "$0")" && pwd)"; RUN="$(cd "$D/../.." && pwd)/.run"; P="$RUN/standby-edge"
NGINX="$(command -v nginx || echo /opt/homebrew/bin/nginx)"
[ -x "$NGINX" ] || { echo "nginx is not installed: brew install nginx"; exit 1; }
PORT="${EDGE_PORT:-443}"
if [ -z "${CERT_DIR:-}" ]; then
  if [ -f "$D/certs/app.team1.test.key" ]; then CERT_DIR="$D/certs"; else CERT_DIR=/opt/homebrew/etc/nginx/certs; fi
fi
for f in app.team1.test.crt app.team1.test.key; do
  [ -r "$CERT_DIR/$f" ] || { echo "Missing the TLS file $f."
    echo "  Put it here:  $D/certs/$f"
    echo "  (the .key comes from Atanu by AirDrop:  mv ~/Downloads/app.team1.test.key \"$D/certs/\")"
    echo "  now in certs/: $(ls "$D/certs" 2>/dev/null | tr '\n' ' ')"; exit 1; }
done
chmod 600 "$CERT_DIR/app.team1.test.key" 2>/dev/null
mkdir -p "$P/tmp"
if [ "$PORT" = 443 ]; then # LAN: let other Macs reach nginx through the macOS Application Firewall
  REAL=$(realpath "$NGINX" 2>/dev/null || echo "$NGINX")
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add "$REAL" >/dev/null 2>&1
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "$REAL" >/dev/null 2>&1
fi
sed -E -e "s#listen 443 ssl;#listen $PORT ssl;#" \
       -e "s#/opt/homebrew/etc/nginx/certs#$CERT_DIR#g" \
       -e "s#/opt/homebrew/var/log/nginx/[a-z0-9_]+\.log#$P/access.log#" \
       "$D/nginx-standby.conf" >"$P/server.conf"
cat >"$P/nginx.conf" <<CONF
worker_processes 1;
pid $P/nginx.pid;
error_log $P/error.log;
events { worker_connections 256; }
http {
    client_body_temp_path $P/tmp/body;
    proxy_temp_path       $P/tmp/proxy;
    fastcgi_temp_path     $P/tmp/fastcgi;
    uwsgi_temp_path       $P/tmp/uwsgi;
    scgi_temp_path        $P/tmp/scgi;
    include $P/server.conf;
}
CONF
"$NGINX" -t -p "$P" -e "$P/error.log" -c "$P/nginx.conf" 2>&1 | grep -v sysctlbyname || true
"$NGINX" -t -q -p "$P" -e "$P/error.log" -c "$P/nginx.conf" 2>/dev/null || { echo "config test FAILED"; exit 1; }
if [ -f "$P/nginx.pid" ] && kill -0 "$(cat "$P/nginx.pid")" 2>/dev/null; then
  "$NGINX" -p "$P" -e "$P/error.log" -c "$P/nginx.conf" -s reload; echo "standby edge reloaded"
else
  "$NGINX" -p "$P" -e "$P/error.log" -c "$P/nginx.conf"; sleep 0.5
fi
CA="$D/../mac2-edge/tls/team1-ca.crt"
echo "Standby edge on :$PORT. Local check (X-Edge must be standby):"
/usr/bin/curl -s -D - -o /dev/null -m 5 --resolve app.team1.test:$PORT:127.0.0.1 --cacert "$CA" \
  https://app.team1.test:$PORT/api/status | grep -iE '^(HTTP|x-edge|x-backend)' | sed 's/^/  /'
echo "Access log: tail -f $P/access.log"
