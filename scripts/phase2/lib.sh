#!/bin/bash
# scripts/phase2/lib.sh - shared helpers for the Phase 2 tests. Source it, don't run it.
#
# MODE=local (default)  Mode 1: whole system on ONE Mac, no sudo.
#     Backends A/B   127.0.0.1:3001 / :3002   (python3 backend/backend.py)
#     Primary DNS    127.0.0.1:5300           (dnsmasq, config derived from config/mac1-dns)
#     Backup DNS     127.0.0.1:5301           (dnsmasq, config derived from config/mac3-backup-dns)
#     Client cache   127.0.0.1:5302           (caching dnsmasq = stand-in for the client's
#                                              mDNSResponder; asks primary, then backup)
#     Primary edge   127.0.0.1:8443           (private nginx, config derived from config/mac2-edge)
#     Second IP      ALT_IP = this Mac's en0 address; used as the "other IP" for the
#                    TTL cutover (Ext B), the standby edge (Ext E) and as a non-edge
#                    client source address (Ext C).
#     Port 5353 is NOT used: it belongs to macOS mDNS.
# MODE=lan  Mode 2: the three real Macs, IPs from lan.env, real ports 53/443/3001/3002.
#
# Bash 3.2 compatible (stock macOS): no associative arrays, no `timeout`, no date +%N.

P2_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$P2_DIR/../.." && pwd)"
. "$P2_DIR/lan.env"

MODE="${MODE:-local}"
DOMAIN=app.team1.test
CURL=/usr/bin/curl                      # never Anaconda's curl (ignores the Keychain)
CA="$REPO/config/mac2-edge/tls/team1-ca.crt"
SIM="${SIM:-$REPO/.sim}"                # runtime dir for Mode 1 (gitignored)
DNSMASQ="$(command -v dnsmasq 2>/dev/null || echo /opt/homebrew/sbin/dnsmasq)"
NGINX="$(command -v nginx 2>/dev/null || echo /opt/homebrew/bin/nginx)"
CERT_DIR="${CERT_DIR:-/opt/homebrew/etc/nginx/certs}"

if [ "$MODE" = "local" ]; then
  EDGE_IP=127.0.0.1;  EDGE_PORT=8443
  BACKEND_IP=127.0.0.1
  DNS1_IP=127.0.0.1;  DNS1_PORT=5300
  DNS2_IP=127.0.0.1;  DNS2_PORT=5301
  CLIENT_DNS_IP=127.0.0.1; CLIENT_DNS_PORT=5302
  ALT_IP="$(/sbin/ifconfig en0 2>/dev/null | awk '/inet /{print $2; exit}')"
  [ -z "$ALT_IP" ] && ALT_IP="$(/sbin/ifconfig 2>/dev/null | awk '/inet / && $2 != "127.0.0.1" {print $2; exit}')"
else
  EDGE_IP=$MAC2_IP;   EDGE_PORT=443
  BACKEND_IP=$MAC3_IP
  DNS1_IP=$MAC1_IP;   DNS1_PORT=53
  DNS2_IP=$MAC3_IP;   DNS2_PORT=53
  ALT_IP=$MAC3_IP     # standby edge
fi

# ---------- output / result helpers ----------
PASSES=0; FAILS=0
section() { printf '\n=== %s ===\n' "$*"; }
say()     { printf '    %s\n' "$*"; }
run()     { printf '  $ %s\n' "$*"; "$@" 2>&1 | sed 's/^/    /'; }
pass()    { PASSES=$((PASSES+1)); printf '  [PASS] %s\n' "$*"; }
fail()    { FAILS=$((FAILS+1));  printf '  [FAIL] %s\n' "$*"; }
expect()  { # expect "description" <command...>   (pass if command exits 0)
  local d="$1"; shift
  if "$@"; then pass "$d"; else fail "$d"; fi
}
summary() {
  printf '\n=== RESULT: %d passed, %d failed (mode=%s) ===\n' "$PASSES" "$FAILS" "$MODE"
  [ "$FAILS" -eq 0 ]
}
pause_lan() { # in LAN mode, ask a human to do something on another Mac
  printf '\n  >>> ACTION: %s\n  >>> Press Enter when done... ' "$*"
  read -r _ </dev/tty
}
# Ext B/E in LAN mode: the client (Mac 1) asks the PRIMARY DNS (itself, 127.0.0.1) first, so only the
# primary's record decides what its cache gets. Humans typing on two Macs take longer than the 30 s
# TTL, so when this test runs ON Mac 1 it changes the primary record itself, with no pause.
on_mac1() { [ -x "$REPO/config/mac1-dns/set_record.sh" ] && ifconfig 2>/dev/null | grep -q "inet $MAC1_IP "; }
lan_primary_set() {
  if on_mac1; then say "Mac 1 changes its own (primary) record now: ./mac1.sh dns-set $1"
    DNS_PORT=53 "$REPO/config/mac1-dns/set_record.sh" "$1" 2>&1 | sed 's/^/      /'
  else pause_lan "Mac 1 (Prince): ./mac1.sh dns-set $1   - FAST, within 5 s (TTL is only 30 s)"; fi
}
lan_backup_set() { pause_lan "On Mac 3 (Sambhav): ./mac3.sh dns-set $1   (backup DNS; not time-critical)"; }

# Tee everything into evidence/phase2/<ext>/<mode>_run.txt.
# Usage at the top of a test:  start_evidence extA "$@"
# (re-runs the script once with its output piped through tee; no /dev/fd needed)
start_evidence() {
  local ext=$1; shift
  if [ -z "${P2_TEED:-}" ]; then
    mkdir -p "$REPO/evidence/phase2/$ext"
    P2_TEED=1 /bin/bash "$0" "$@" 2>&1 | tee "$REPO/evidence/phase2/$ext/${MODE}_run.txt"
    exit "${PIPESTATUS[0]}"
  fi
  echo "# $ext test - mode=$MODE - $(date '+%Y-%m-%d %H:%M:%S %Z') - host=$(hostname -s)"
}

# ---------- DNS helpers ----------
# resolve <server> <port> [name] -> first A record, or empty
resolve() {
  dig +short +time=1 +tries=2 @"$1" -p "$2" "${3:-$DOMAIN}" A 2>/dev/null \
    | grep -E '^[0-9]+(\.[0-9]+){3}$' | head -1
}
# ttl_of <server> <port> [name] -> TTL of the first A record
ttl_of() {
  dig +noall +answer +time=1 +tries=2 @"$1" -p "$2" "${3:-$DOMAIN}" A 2>/dev/null \
    | awk '$4=="A"{print $2; exit}'
}
# dns_dead <server> <port> -> true if the server gives no answer at all
dns_dead() { ! dig +time=1 +tries=1 @"$1" -p "$2" "$DOMAIN" A >/dev/null 2>&1; }

# ---------- HTTPS helpers (real SNI + cert validation, never -k) ----------
# Mode 1: connect to <ip> via --resolve, trust our CA file.
# Mode 2: if <ip> is empty, use real DNS; trust comes from the Keychain (team1 CA installed).
_target() { # _target <ip> <path>  -> sets CURL_ARGS
  if [ "$MODE" = "local" ]; then
    CURL_ARGS=(--resolve "$DOMAIN:$EDGE_PORT:$1" --cacert "$CA" "https://$DOMAIN:$EDGE_PORT$2")
  elif [ -n "$1" ]; then
    CURL_ARGS=(--resolve "$DOMAIN:443:$1" "https://$DOMAIN$2")
  else
    CURL_ARGS=("https://$DOMAIN$2")
  fi
}
# https_code <ip> [path] -> HTTP status code ("000" = no TCP/TLS connection)
https_code() {
  _target "$1" "${2:-/api/status}"
  $CURL -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 6 "${CURL_ARGS[@]}" 2>/dev/null
}
# https_hdr <ip> <header> [path] -> value of a response header (e.g. X-Backend)
https_hdr() {
  _target "$1" "${3:-/api/status}"
  $CURL -s -D - -o /dev/null --connect-timeout 3 --max-time 6 "${CURL_ARGS[@]}" 2>/dev/null \
    | awk -v h="$(echo "$2" | tr 'A-Z' 'a-z')" -F': ' 'tolower($1)==h{gsub("\r","",$2); print $2}'
}
# probe <ip> -> "<code> backend=<A|B|-> edge=<primary|standby|->"  (one request)
probe() {
  _target "$1" /api/status
  $CURL -s -D - -o /dev/null --connect-timeout 3 --max-time 6 "${CURL_ARGS[@]}" 2>/dev/null | awk '
    /^HTTP/ {c=$2} tolower($1)=="x-backend:" {b=$2} tolower($1)=="x-edge:" {e=$2}
    END {gsub("\r","",b); gsub("\r","",e); printf "%s backend=%s edge=%s\n", (c?c:"000"), (b?b:"-"), (e?e:"-")}'
}

# ---------- Mode 1 fixture helpers ----------
port_open() { /usr/bin/nc -z -G 1 "$1" "$2" >/dev/null 2>&1; }   # TCP listener present?
wait_tcp() { # wait_tcp ip port  (max ~5 s)
  local i=0; while [ $i -lt 50 ]; do port_open "$1" "$2" && return 0; sleep 0.1; i=$((i+1)); done
  echo "timeout waiting for $1:$2" >&2; return 1
}
wait_dns() { # wait_dns ip port (max ~5 s)
  local i=0; while [ $i -lt 25 ]; do
    dig +time=1 +tries=1 @"$1" -p "$2" "$DOMAIN" >/dev/null 2>&1 && return 0; sleep 0.2; i=$((i+1)); done
  echo "timeout waiting for DNS $1:$2" >&2; return 1
}
pid_of()  { cat "$SIM/$1.pid" 2>/dev/null; }
stop()    { # stop <name>  - TERM the process recorded in $SIM/<name>.pid
  local p; p="$(pid_of "$1")"
  [ -n "$p" ] && kill "$p" 2>/dev/null
  rm -f "$SIM/$1.pid"; sleep 0.3
}
hup()     { kill -HUP "$(pid_of "$1")"; }

start_backend() { # start_backend A 3001
  port_open 127.0.0.1 "$2" && { echo "port $2 already in use - stop it first" >&2; return 1; }
  python3 -u "$REPO/backend/backend.py" "$1" "$2" >"$SIM/backend_$1.log" 2>&1 </dev/null &
  echo $! >"$SIM/backend_$1.pid"; disown
  wait_tcp 127.0.0.1 "$2"
}

# Records file shared by the local primary + backup (one edit updates both).
set_record() { # set_record <ip>
  printf '%s app.team1.test api.team1.test\n' "$1" >"$SIM/team1.hosts"
}

# Derive a Mode 1 dnsmasq config from the real Mode 2 file: drop LAN-only lines
# (interface, listen address, upstream servers, paths) and add loopback ones.
# Everything else (local=/team1.test/, local-ttl, domain-needed...) is the real config.
start_dns() { # start_dns <name> <src-conf> <port>
  local name=$1 src=$2 port=$3 conf="$SIM/$1.conf"
  [ -x "$DNSMASQ" ] || { echo "dnsmasq not installed: brew install dnsmasq" >&2; return 1; }
  sed -E '/^(interface|listen-address|addn-hosts|log-facility|server)=/d' "$src" >"$conf"
  cat >>"$conf" <<EOF
# --- Mode 1 overrides (added by lib.sh) ---
port=$port
listen-address=127.0.0.1
bind-interfaces
no-hosts
addn-hosts=$SIM/team1.hosts
log-facility=$SIM/$name.log
pid-file=
EOF
  "$DNSMASQ" --keep-in-foreground -C "$conf" >>"$SIM/$name.out" 2>&1 </dev/null &
  echo $! >"$SIM/$name.pid"; disown
  wait_dns 127.0.0.1 "$port"
}

# The client-side cache: a caching dnsmasq that knows two upstream servers in
# order (primary, then backup) - what a Mac does with two DNS servers listed.
start_client_resolver() {
  cat >"$SIM/dns_client.conf" <<EOF
port=$CLIENT_DNS_PORT
listen-address=127.0.0.1
bind-interfaces
no-resolv
no-hosts
strict-order
server=/team1.test/127.0.0.1#$DNS1_PORT
server=/team1.test/127.0.0.1#$DNS2_PORT
cache-size=150
log-queries
log-facility=$SIM/dns_client.log
pid-file=
EOF
  "$DNSMASQ" --keep-in-foreground -C "$SIM/dns_client.conf" >>"$SIM/dns_client.out" 2>&1 </dev/null &
  echo $! >"$SIM/dns_client.pid"; disown
  wait_dns 127.0.0.1 "$CLIENT_DNS_PORT"
}

# Derive a Mode 1 nginx from the real Mode 2 server block: backends -> 127.0.0.1,
# listen 443 -> <ip>:8443, log paths -> $SIM. Same upstream / HA / TLS settings.
start_nginx() { # start_nginx <name> <src-conf> <listen-ip>
  local name=$1 src=$2 ip=$3 d="$SIM/$1"
  [ -r "$CERT_DIR/app.team1.test.key" ] || { echo "missing $CERT_DIR/app.team1.test.key" >&2; return 1; }
  mkdir -p "$d/tmp"; : >"$d/access.log"     # fresh log per run (evidence must not mix runs)
  sed -E -e "s#[0-9]+(\.[0-9]+){3}:(300[12])#$BACKEND_IP:\2#g" \
         -e "s#listen 443 ssl;#listen $ip:$EDGE_PORT ssl;#" \
         -e "s#/opt/homebrew/var/log/nginx/[a-z0-9_]+\.log#$d/access.log#" \
         -e "s#/opt/homebrew/etc/nginx/certs#$CERT_DIR#g" \
         "$src" >"$d/server.conf"
  cat >"$d/nginx.conf" <<EOF
worker_processes 1;
pid $d/nginx.pid;
error_log $d/error.log;
events { worker_connections 256; }
http {
    client_body_temp_path $d/tmp/body;
    proxy_temp_path       $d/tmp/proxy;
    fastcgi_temp_path     $d/tmp/fastcgi;
    uwsgi_temp_path       $d/tmp/uwsgi;
    scgi_temp_path        $d/tmp/scgi;
    include $d/server.conf;
}
EOF
  "$NGINX" -t -q -p "$d" -e "$d/error.log" -c "$d/nginx.conf" || return 1
  "$NGINX" -p "$d" -e "$d/error.log" -c "$d/nginx.conf" -g 'daemon off;' >"$d/stdout.log" 2>&1 </dev/null &
  echo $! >"$SIM/$name.pid"; disown
  wait_tcp "$ip" "$EDGE_PORT"
}

_kill_all() { local f; for f in "$SIM"/*.pid; do [ -e "$f" ] && stop "$(basename "$f" .pid)"; done; return 0; }

# Only one Mode 1 test may own the stack at a time (they share ports and $SIM).
sim_lock() {
  mkdir -p "$SIM"
  if ! mkdir "$SIM/lock" 2>/dev/null; then
    local owner; owner="$(cat "$SIM/lock/pid" 2>/dev/null)"
    if [ "$owner" = "persistent" ]; then
      echo "A long-running stack from sim_up.sh is active. Stop it first: ./scripts/phase2/sim_down.sh" >&2; return 1
    fi
    if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null; then
      echo "Another Phase 2 test (pid $owner) is running. Run the tests one at a time." >&2; return 1
    fi
    rm -rf "$SIM/lock"; mkdir "$SIM/lock" || return 1     # stale lock from a crashed run
  fi
  echo $$ >"$SIM/lock/pid"; SIM_LOCKED=1
}
sim_down() {
  [ -n "${SIM_LOCKED:-}" ] || return 0      # never tear down a stack we don't own
  _kill_all; rm -rf "$SIM/lock"; SIM_LOCKED=""
  return 0
}

# Standard Mode 1 stack used by most tests: 2 backends, primary edge, primary +
# backup DNS (record -> 127.0.0.1) and the client cache.
sim_up() {
  sim_lock || return 1
  _kill_all
  set_record "$EDGE_IP"
  start_backend A 3001 &&
  start_backend B 3002 &&
  start_nginx edge_primary "$REPO/config/mac2-edge/nginx/team1-phase2.conf" "$EDGE_IP" &&
  start_dns dns_primary "$REPO/config/mac1-dns/dnsmasq.conf" "$DNS1_PORT" &&
  start_dns dns_backup  "$REPO/config/mac3-backup-dns/dnsmasq-backup.conf" "$DNS2_PORT" &&
  start_client_resolver
}

# Is a Mode 1 stack running right now (from sim_up.sh or a test)?
sim_running() { [ -d "$SIM/lock" ] && [ -f "$SIM/edge_primary.pid" ] && kill -0 "$(pid_of edge_primary)" 2>/dev/null; }
