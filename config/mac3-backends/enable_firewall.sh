#!/bin/bash
# Ext C - turn ON the backend firewall (Mac 3). Needs sudo.
#   ./enable_firewall.sh            LAN: only Mac 2 (10.7.16.45) may reach :3001/:3002 over Wi-Fi
#   ./enable_firewall.sh --local    Mode 1 (one Mac): only 127.0.0.1 may reach them on lo0
# Rollback: ./disable_firewall.sh
# Overrides: EDGE_IP=... EXT_IF=en1 ./enable_firewall.sh
set -u
D="$(cd "$(dirname "$0")" && pwd)"
ANCHOR=com.apple/team1
STATE="${PF_STATE:-$HOME/team1-pf-backup}"

if [ "${1:-}" = "--local" ]; then
  EXT_IF=lo0; EDGE=127.0.0.1
else
  EDGE="${EDGE_IP:-10.7.16.45}"
  EXT_IF="${EXT_IF:-$(networksetup -listallhardwareports | awk '/Hardware Port: Wi-Fi/{getline; print $2; exit}')}"
fi
[ -n "$EXT_IF" ] || { echo "Could not find the Wi-Fi interface. Run: EXT_IF=en0 $0"; exit 1; }

mkdir -p "$STATE"
TS=$(date +%Y%m%d-%H%M%S)
echo "[1/4] Rollback copy of the current pf state -> $STATE/"
sudo pfctl -s info 2>/dev/null | head -1           >"$STATE/before_${TS}_status.txt"
sudo pfctl -sr 2>/dev/null                         >"$STATE/before_${TS}_rules.txt"
sudo pfctl -a "$ANCHOR" -sr 2>/dev/null            >"$STATE/before_${TS}_anchor.txt"
cp "$STATE/before_${TS}_rules.txt" "$STATE/latest_rules_before.txt"
echo "      status before: $(cat "$STATE/before_${TS}_status.txt")"

echo "[2/4] Main ruleset must reference the com.apple/* anchors (macOS default /etc/pf.conf)"
if ! grep -q 'anchor "com.apple/\*"' "$STATE/before_${TS}_rules.txt"; then
  echo "      not loaded -> loading Apple's default /etc/pf.conf"
  sudo pfctl -q -f /etc/pf.conf 2>/dev/null
fi

echo "[3/4] Loading $D/pf_team1.conf into anchor $ANCHOR (ext_if=$EXT_IF edge=$EDGE)"
# (pfctl always prints a generic "Use of -f option" warning; it does not apply to anchors)
sudo pfctl -q -a "$ANCHOR" -D "ext_if=$EXT_IF" -D "edge=$EDGE" -f "$D/pf_team1.conf" 2>"$STATE/load_err.txt" \
  || { cat "$STATE/load_err.txt"; exit 1; }
sudo pfctl -a "$ANCHOR" -sr 2>/dev/null | sed 's/^/      /'

echo "[4/4] Enabling pf (reference-counted token, so disabling never breaks other pf users)"
OUT=$(sudo pfctl -E 2>&1)
TOKEN=$(echo "$OUT" | awk '/Token/{print $NF}')
[ -n "$TOKEN" ] && echo "$TOKEN" >"$STATE/token"
echo "$OUT" | grep -iE 'enabled|token' | sed 's/^/      /'
echo "Firewall ON. Test from another Mac: curl -m 3 http://<mac3>:3001/  -> must time out."
