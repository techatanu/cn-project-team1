#!/bin/bash
# Ext C - ROLLBACK: remove the team1 pf rules and restore the original pf state. Needs sudo.
# Safe to run any time, even twice. Only touches the com.apple/team1 anchor.
set -u
ANCHOR=com.apple/team1
STATE="${PF_STATE:-$HOME/team1-pf-backup}"

echo "[1/3] Flushing anchor $ANCHOR"
sudo pfctl -q -a "$ANCHOR" -F all 2>/dev/null

echo "[2/3] Releasing our pf enable token"
if [ -f "$STATE/token" ]; then
  sudo pfctl -X "$(cat "$STATE/token")" 2>&1 | sed 's/^/      /'
  rm -f "$STATE/token"
else
  echo "      no token saved (pf was not enabled by enable_firewall.sh)"
fi

echo "[3/3] Verifying the original configuration is back"
LEFT=$(sudo pfctl -a "$ANCHOR" -sr 2>/dev/null)
[ -z "$LEFT" ] && echo "      anchor $ANCHOR is empty: OK" || { echo "      anchor still has rules:"; echo "$LEFT"; }
if [ -f "$STATE/latest_rules_before.txt" ]; then
  if sudo pfctl -sr 2>/dev/null | diff -q - "$STATE/latest_rules_before.txt" >/dev/null; then
    echo "      main ruleset identical to the rollback copy: OK"
  else
    echo "      main ruleset differs from the rollback copy ($STATE/latest_rules_before.txt):"
    sudo pfctl -sr 2>/dev/null | diff - "$STATE/latest_rules_before.txt" | sed 's/^/        /'
  fi
fi
echo "      pf $(sudo pfctl -s info 2>/dev/null | head -1)"
echo "Firewall OFF (rolled back)."
