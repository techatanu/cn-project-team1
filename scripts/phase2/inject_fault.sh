#!/bin/bash
# Extension F - inject ONE realistic fault so the team can practise layer-by-layer diagnosis.
#   ./inject_fault.sh dns-wrong-ip                 DNS : app.team1.test -> 10.7.31.250 (wrong IP)
#   ./inject_fault.sh tcp-port-blocked [backend]   TCP : pf drops edge -> backend ports 3001/3002  (sudo)
#   ./inject_fault.sh tcp-port-blocked edge        TCP : pf drops client -> edge port 443/8443     (sudo)
#   ./inject_fault.sh tls-cert-mismatch            TLS : edge serves a cert for wrong.team1.test
#   ./inject_fault.sh restore                      undo whatever is injected
#   ./inject_fault.sh status
# Mode 1 (default): acts on the stack from sim_up.sh on this Mac.
# Mode 2: MODE=lan ...  dns-wrong-ip runs on Mac 1; the other faults run on Mac 2 (the edge).
# Then diagnose with:  ./diagnose.sh   (MODE=lan ./diagnose.sh on a client)
. "$(dirname "$0")/lib.sh"
WRONG_IP=10.7.31.250                 # in our /19 subnet, but no machine has it
ANCHOR=com.apple/team1-fault
if [ "$MODE" = "local" ]; then STATE="$SIM"; else STATE="$HOME/.team1-fault"; fi
mkdir -p "$STATE"; F="$STATE/fault"
CA_KEY="${CA_KEY:-$HOME/cn-project/certs/team1-ca.key}"
LAN_CONF=/opt/homebrew/etc/nginx/servers/team1-phase2.conf
LAN_HOSTS=/opt/homebrew/etc/team1.hosts

on_mac() { /sbin/ifconfig | grep -q "inet $1 " || { echo "Run this fault on the Mac with IP $1 ($2)."; exit 1; }; }
need_sim() { [ "$MODE" = "lan" ] || sim_running || { echo "Mode 1 stack not running. Start it: ./scripts/phase2/sim_up.sh"; exit 1; }; }
reload_edge() {
  if [ "$MODE" = "local" ]; then kill -HUP "$(pid_of edge_primary)"; sleep 0.5
  else nginx -t && nginx -s reload; fi
}
pf_on() { # pf_on "<rule>"
  echo "$1" | sudo pfctl -q -a "$ANCHOR" -f - 2>/dev/null || { echo "pfctl failed"; exit 1; }
  sudo pfctl -E 2>&1 | awk '/Token/{print $NF}' >"$STATE/pf_token"
  echo "pf rule loaded in anchor $ANCHOR:"; sudo pfctl -a "$ANCHOR" -sr 2>/dev/null | sed 's/^/  /'
}
pf_off() {
  sudo pfctl -q -a "$ANCHOR" -F all 2>/dev/null
  [ -s "$STATE/pf_token" ] && sudo pfctl -X "$(cat "$STATE/pf_token")" >/dev/null 2>&1
  rm -f "$STATE/pf_token"
}
make_wrong_cert() { # cert whose SAN is wrong.team1.test, signed by our own CA if its key is here
  local d=$1; mkdir -p "$d"
  [ -f "$d/wrong.crt" ] && return 0
  openssl genrsa -out "$d/wrong.key" 2048 2>/dev/null
  openssl req -new -key "$d/wrong.key" -subj "/C=IN/O=Team1 CN Project/CN=wrong.team1.test" -out "$d/wrong.csr" 2>/dev/null
  printf 'basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:wrong.team1.test\n' >"$d/wrong.ext"
  if [ -r "$CA_KEY" ]; then
    openssl x509 -req -in "$d/wrong.csr" -CA "$CA" -CAkey "$CA_KEY" -CAcreateserial -CAserial "$d/ca.srl" \
      -days 30 -sha256 -extfile "$d/wrong.ext" -out "$d/wrong.crt" 2>/dev/null
    echo "fault cert: CN/SAN wrong.team1.test, signed by Team1 Local CA (pure NAME mismatch)"
  else
    openssl x509 -req -in "$d/wrong.csr" -signkey "$d/wrong.key" -days 30 -sha256 -extfile "$d/wrong.ext" -out "$d/wrong.crt" 2>/dev/null
    echo "fault cert: self-signed wrong.team1.test (CA key not found: name mismatch AND untrusted)"
  fi
  chmod 600 "$d/wrong.key"
}

[ -f "$F" ] && [ "${1:-}" != restore ] && [ "${1:-}" != status ] && { echo "Fault '$(cat "$F")' is already injected. Run: $0 restore"; exit 1; }

case "${1:-}" in
  dns-wrong-ip)
    need_sim
    if [ "$MODE" = "local" ]; then
      set_record "$WRONG_IP"; hup dns_primary; hup dns_backup; hup dns_client
    else
      on_mac "$MAC1_IP" "Mac 1, primary DNS"
      cp "$LAN_HOSTS" "$STATE/team1.hosts.orig"
      printf '%s app.team1.test api.team1.test\n' "$WRONG_IP" >"$LAN_HOSTS"; sudo killall -HUP dnsmasq
    fi
    echo dns-wrong-ip >"$F"
    echo "INJECTED: DNS now answers $DOMAIN -> $WRONG_IP (edge is $EDGE_IP)." ;;

  tcp-port-blocked)
    need_sim; target="${2:-backend}"
    if [ "$MODE" = "local" ]; then
      [ "$target" = edge ] && rule="block drop in quick on lo0 proto tcp to any port $EDGE_PORT" \
                           || rule="block drop out quick on lo0 proto tcp to any port { 3001, 3002 }"
    else
      on_mac "$MAC2_IP" "Mac 2, edge"
      [ "$target" = edge ] && rule="block drop in quick proto tcp to any port 443" \
                           || rule="block drop out quick proto tcp to $MAC3_IP port { 3001, 3002 }"
    fi
    pf_on "$rule"; echo "tcp-port-blocked-$target" >"$F"
    echo "INJECTED: TCP to the $target port(s) is silently dropped." ;;

  tls-cert-mismatch)
    need_sim
    if [ "$MODE" = "local" ]; then
      C="$SIM/edge_primary/server.conf"; make_wrong_cert "$SIM/fault-certs"
      cp "$C" "$C.orig"
      sed -i '' -E "s#ssl_certificate +[^;]+;#ssl_certificate     $SIM/fault-certs/wrong.crt;#; s#ssl_certificate_key +[^;]+;#ssl_certificate_key $SIM/fault-certs/wrong.key;#" "$C"
    else
      on_mac "$MAC2_IP" "Mac 2, edge"; make_wrong_cert /opt/homebrew/etc/nginx/certs/fault
      cp "$LAN_CONF" "$STATE/team1-phase2.conf.orig"
      sed -i '' -E "s#ssl_certificate +[^;]+;#ssl_certificate     /opt/homebrew/etc/nginx/certs/fault/wrong.crt;#; s#ssl_certificate_key +[^;]+;#ssl_certificate_key /opt/homebrew/etc/nginx/certs/fault/wrong.key;#" "$LAN_CONF"
    fi
    reload_edge; echo tls-cert-mismatch >"$F"
    echo "INJECTED: the edge now presents a certificate for wrong.team1.test." ;;

  restore)
    [ -f "$F" ] || { echo "No fault injected."; exit 0; }
    case "$(cat "$F")" in
      dns-wrong-ip)
        if [ "$MODE" = "local" ]; then set_record "$EDGE_IP"; hup dns_primary; hup dns_backup; hup dns_client
        else cp "$STATE/team1.hosts.orig" "$LAN_HOSTS"; sudo killall -HUP dnsmasq; fi ;;
      tcp-port-blocked-*) pf_off ;;
      tls-cert-mismatch)
        if [ "$MODE" = "local" ]; then mv "$SIM/edge_primary/server.conf.orig" "$SIM/edge_primary/server.conf"
        else cp "$STATE/team1-phase2.conf.orig" "$LAN_CONF"; fi
        reload_edge ;;
    esac
    echo "RESTORED (was: $(cat "$F"))."; rm -f "$F" ;;

  status) [ -f "$F" ] && echo "injected: $(cat "$F")" || echo "no fault injected" ;;
  *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
