#!/bin/bash
# Extension F - systematic, layer-by-layer diagnosis of https://app.team1.test
#   Layer 1 DNS  -> Layer 2 TCP -> Layer 3 TLS -> Layer 4 HTTP   (stops at the first failing layer)
# Mode 1: ./diagnose.sh               (against the stack started by sim_up.sh / a test)
# Mode 2: MODE=lan ./diagnose.sh      (on any client Mac, uses this Mac's real DNS settings)
# Exit code = failing layer: 0 all OK, 1 DNS, 2 TCP, 3 TLS, 4 HTTP.
# Override the IP you expect DNS to return (e.g. during Ext E): EXPECT_IP=10.7.24.9
. "$(dirname "$0")/lib.sh"
EXPECT="${EXPECT_IP:-$EDGE_IP}"; mkdir -p "$SIM"
step() { printf '\n[%s] %s\n' "$1" "$2"; }
cmd()  { printf '  $ %s\n' "$*"; }
verdict() { # verdict <layer-no> <layer> <cause> <check/fix lines...>
  local n=$1 l=$2 c=$3; shift 3
  printf '\n  >>> VERDICT: fault at the %s layer (layer %s): %s\n' "$l" "$n" "$c"
  local x; for x in "$@"; do printf '      - %s\n' "$x"; done
  exit "$n"
}
echo "Diagnosing https://$DOMAIN  (mode=$MODE, expected edge IP $EXPECT, port $EDGE_PORT)"

# ---------------- Layer 1: DNS ----------------
step "1/4 DNS" "Does $DOMAIN resolve, and to the EDGE's IP?"
if [ "$MODE" = "local" ]; then
  cmd dig @"$CLIENT_DNS_IP" -p "$CLIENT_DNS_PORT" "$DOMAIN"
  OUT=$(dig +time=2 +tries=1 @"$CLIENT_DNS_IP" -p "$CLIENT_DNS_PORT" "$DOMAIN" A 2>&1)
else
  cmd dig "$DOMAIN"; OUT=$(dig +time=2 +tries=1 "$DOMAIN" A 2>&1)
fi
echo "$OUT" | grep -E 'status:|IN[[:space:]]+A[[:space:]]|SERVER:|timed out' | sed 's/^/    /'
IP=$(echo "$OUT" | awk '$4=="A"{print $5; exit}')
if [ -z "$IP" ]; then
  verdict 1 DNS "no A record returned (server down, NXDOMAIN or wrong resolver)" \
    "which server did we ask?  scutil --dns | grep nameserver   (should list Mac 1 and Mac 3)" \
    "ask each server directly: dig @$DNS1_IP -p $DNS1_PORT $DOMAIN ; dig @$DNS2_IP -p $DNS2_PORT $DOMAIN" \
    "on the DNS Mac: sudo brew services list | grep dnsmasq ; sudo lsof -nP -i :53 ; tail /tmp/dnsmasq.log"
fi
if [ "$IP" != "$EXPECT" ]; then
  verdict 1 DNS "resolves to $IP but the edge is $EXPECT (wrong record)" \
    "compare servers: dig +short @$DNS1_IP -p $DNS1_PORT $DOMAIN ; dig +short @$DNS2_IP -p $DNS2_PORT $DOMAIN" \
    "fix the record on the DNS Mac: cat /opt/homebrew/etc/team1.hosts ; ./set_record.sh $EXPECT (sends SIGHUP)" \
    "then flush the client: sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"
fi
echo "  [OK] $DOMAIN -> $IP (the edge)"

# ---------------- Layer 2: TCP ----------------
step "2/4 TCP" "Can we complete the 3-way handshake to $IP:$EDGE_PORT?"
cmd curl --connect-timeout 3 "http://$IP:$EDGE_PORT/"   "(exit 7 = refused, 28 = timeout)"
$CURL -s -o /dev/null --connect-timeout 3 --max-time 4 "http://$IP:$EDGE_PORT/" 2>/dev/null; RC=$?
case $RC in
  7)  verdict 2 TCP "connection REFUSED: host is up and answered with RST, nothing listens on $EDGE_PORT" \
        "on the edge: lsof -nP -iTCP:$EDGE_PORT -sTCP:LISTEN  (nginx running? right listen port?)" \
        "start / check nginx: nginx -t && nginx ; tail /opt/homebrew/var/log/nginx/error.log" ;;
  28) verdict 2 TCP "connection TIMED OUT: SYNs get no answer -> dropped by a firewall, or host unreachable" \
        "is the host up? ping -c 3 $IP" \
        "firewall on the edge? sudo pfctl -s info | head -1 ; sudo pfctl -sr ; sudo pfctl -a com.apple/team1-fault -sr" \
        "Wireshark/tcpdump: tcp.port==$EDGE_PORT shows SYN retransmissions, never a SYN-ACK" ;;
esac
echo "  [OK] TCP handshake to $IP:$EDGE_PORT completed"

# ---------------- Layer 3: TLS ----------------
step "3/4 TLS" "Does the certificate validate for $DOMAIN (trusted CA + matching name)?"
_target "$IP" /api/status
cmd curl -sS -o /dev/null -w '%{http_code}' "${CURL_ARGS[@]}"
ERR=$($CURL -sS -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 8 "${CURL_ARGS[@]}" 2>&1 >"$SIM/.code" ); RC=$?
CODE=$(cat "$SIM/.code" 2>/dev/null); rm -f "$SIM/.code"
CERT=$(echo | openssl s_client -connect "$IP:$EDGE_PORT" -servername "$DOMAIN" 2>/dev/null | openssl x509 -noout -subject -issuer -text 2>/dev/null \
       | grep -E '^(subject|issuer)=|DNS:' | sed 's/^ *//')
echo "  certificate presented by the server:"; echo "$CERT" | sed 's/^/    /'
case $RC in
  60|51) verdict 3 TLS "certificate rejected by the client: $ERR" \
        "name mismatch -> the SAN above must contain DNS:$DOMAIN (nginx ssl_certificate points at the wrong file?)" \
        "untrusted issuer -> install team1-ca.crt: sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain team1-ca.crt" \
        "on the edge: grep ssl_certificate /opt/homebrew/etc/nginx/servers/*.conf ; nginx -t ; nginx -s reload" ;;
  35|58|59|53|54|66|80|83|90|91) verdict 3 TLS "TLS handshake failed: $ERR" \
        "openssl s_client -connect $IP:$EDGE_PORT -servername $DOMAIN  (protocol / cipher / key problem)" ;;
esac
[ "$RC" -ne 0 ] && [ -z "$CODE" -o "$CODE" = "000" ] && verdict 3 TLS "curl failed during/after TLS: $ERR (exit $RC)" "re-run with: curl -v ..."
echo "  [OK] certificate trusted and valid for $DOMAIN (no -k used)"

# ---------------- Layer 4: HTTP ----------------
step "4/4 HTTP" "Does the application answer correctly through the edge?"
P=$(probe "$( [ "$MODE" = local ] && echo "$IP" || echo "" )")
echo "    HTTP $P"
case "$CODE" in
  200) echo "  [OK] HTTP 200 - all four layers healthy"; exit 0 ;;
  502|504) verdict 4 HTTP "edge is fine but cannot get an answer from the backends (HTTP $CODE)" \
        "502 = backend refused/closed (process down); 504 = backend timed out (firewall drop / hung)" \
        "on the edge: tail -n 5 /opt/homebrew/var/log/nginx/error.log   (connect() failed / upstream timed out)" \
        "from the edge: curl -m 3 http://$MAC3_IP:3001/api/status ; curl -m 3 http://$MAC3_IP:3002/api/status" \
        "on Mac 3: ./mac3.sh status ; sudo pfctl -a com.apple/team1 -sr" ;;
  *) verdict 4 HTTP "unexpected HTTP status $CODE" "curl -v https://$DOMAIN/api/status ; check nginx location / proxy_pass" ;;
esac
