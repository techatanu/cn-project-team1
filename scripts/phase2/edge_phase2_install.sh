#!/bin/bash
# Mac 2 (Atanu) - switch the LIVE edge nginx from the Phase 1 config to Phase 2, or back.
#   ./edge_phase2_install.sh install    servers/team1.conf -> ~/cn-project/phase1-team1.conf.bak,
#                                       copy team1-phase2.conf into servers/, nginx -t, reload/start
#   ./edge_phase2_install.sh rollback   put the Phase 1 config back
#   ./edge_phase2_install.sh status
# Both files define the same upstream, so they must never be in servers/ together
# (nginx.conf has `include servers/*;`). No sudo needed (nginx listens on 443 as the user).
set -u
P2="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$P2/../.." && pwd)"
SRV=/opt/homebrew/etc/nginx/servers
BAK="$HOME/cn-project/phase1-team1.conf.bak"
NEWCONF="$REPO/config/mac2-edge/nginx/team1-phase2.conf"

# Run this in Terminal.app, NOT from a restricted (sandboxed) shell: it cannot see the running nginx,
# so it can neither find nor signal it (23 Nov 15:15: "bind() ... Address already in use").
apply_running() { # signal the running nginx via its pid file; start it only if none is running
  if nginx -s reload 2>/dev/null; then echo "nginx reloaded"
  elif nginx 2>/dev/null; then echo "nginx started"
  else echo "ERROR: could not reload or start nginx. The config on disk is fine; run in Terminal.app:  nginx -s reload"; return 1; fi
}
case "${1:-status}" in
  install)
    mkdir -p "$(dirname "$BAK")"
    if [ -f "$SRV/team1.conf" ]; then mv "$SRV/team1.conf" "$BAK"; echo "Phase 1 config saved to $BAK"; fi
    cp "$NEWCONF" "$SRV/team1-phase2.conf"
    if ! nginx -t; then # only a BAD CONFIG is rolled back; a failed signal leaves the new file in place
      echo "nginx -t FAILED - rolling back to Phase 1"; rm -f "$SRV/team1-phase2.conf"; [ -f "$BAK" ] && cp "$BAK" "$SRV/team1.conf"; exit 1
    fi
    apply_running || exit 1
    sleep 1
    /usr/bin/curl -s -D - -o /dev/null https://app.team1.test/api/status | grep -iE '^(HTTP|x-edge|x-backend)' ;;
  rollback)
    rm -f "$SRV/team1-phase2.conf"
    [ -f "$BAK" ] && cp "$BAK" "$SRV/team1.conf" && echo "Phase 1 config restored"
    nginx -t && apply_running ;;
  status)
    ls -l "$SRV"/
    grep -hE 'server [0-9.]+:300|fail_timeout|proxy_connect_timeout|X-Edge' "$SRV"/*.conf 2>/dev/null | sed 's/^/  /'
    [ -f "$SRV/team1-phase2.conf" ] && [ ! -f "$SRV/team1.conf" ] && echo "  OK: only the Phase 2 config is on disk" \
      || echo "  WARNING: Phase 2 config is not (only) what is on disk - run: $0 install" ;;
  *) sed -n '2,8p' "$0"; exit 1 ;;
esac
