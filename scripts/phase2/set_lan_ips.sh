#!/bin/bash
# Change the LAN IPs of the three Macs everywhere Phase 2 uses them, then rebuild the teammate zips.
#   ./scripts/phase2/set_lan_ips.sh <mac1-ip> <mac2-ip> <mac3-ip>
#   ./scripts/phase2/set_lan_ips.sh --check        only verify that every Phase 2 file agrees with lan.env
# The current values are read from scripts/phase2/lan.env. Phase 1 documents/evidence are NOT touched
# (they record what was true in Phase 1).
set -u
P2="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$P2/../.." && pwd)"; cd "$REPO"
. "$P2/lan.env"

# Every Phase 2 file that contains a Mac's LAN IP
FILES="scripts/phase2/lan.env
config/mac1-dns/dnsmasq.conf config/mac1-dns/team1.hosts config/mac1-dns/set_record.sh config/mac1-dns/README.md
config/mac2-edge/nginx/team1-phase2.conf
config/mac3-backup-dns/dnsmasq-backup.conf config/mac3-backup-dns/team1.hosts config/mac3-backup-dns/set_record.sh
config/mac3-backends/enable_firewall.sh config/mac3-backends/pf_team1.conf
config/mac3-standby-edge/nginx-standby.conf
scripts/phase2/diagnose.sh scripts/phase2/test_extB_ttl_cutover.sh scripts/phase2/test_extD_ha_failover.sh
scripts/phase2/test_mac1_package.sh scripts/phase2/test_mac3_package.sh scripts/phase2/edge_phase2_install.sh
teammates/README_PRINCE.md teammates/README_SAMBHAV.md teammates/mac1.sh teammates/mac3.sh
docs/ExtensionF_Troubleshooting_Guide.md docs/Phase2_LAN_Runsheet.html docs/Phase2_Report.md
docs/diagrams/topology_phase2.svg dist/Phase2_LAN_Commands.txt"

in_subnet() { # our Wi-Fi: 10.7.0.0/19 -> 10.7.0.x .. 10.7.31.x
  echo "$1" | awk -F. '{exit !($1==10 && $2==7 && $3>=0 && $3<=31 && $4>=1 && $4<=254)}'
}

check() {
  local bad=0
  echo "lan.env: Mac 1 = $MAC1_IP   Mac 2 = $MAC2_IP   Mac 3 = $MAC3_IP"
  for ip in "$MAC1_IP" "$MAC2_IP" "$MAC3_IP"; do
    in_subnet "$ip" && echo "  [OK] $ip is inside 10.7.0.0/19" || { echo "  [FAIL] $ip is NOT in 10.7.0.0/19"; bad=1; }
  done
  grep -q "server $MAC3_IP:3001" config/mac2-edge/nginx/team1-phase2.conf && grep -q "server $MAC3_IP:3002" config/mac2-edge/nginx/team1-phase2.conf \
    && echo "  [OK] edge upstream -> $MAC3_IP:3001/3002" || { echo "  [FAIL] edge upstream does not point to $MAC3_IP"; bad=1; }
  for h in config/mac1-dns/team1.hosts config/mac3-backup-dns/team1.hosts; do
    grep -q "^$MAC2_IP app.team1.test api.team1.test" "$h" \
      && echo "  [OK] $h: app/api -> $MAC2_IP (the edge)" || { echo "  [FAIL] $h does not point to the edge $MAC2_IP"; bad=1; }
  done
  grep -q "EDGE_IP:-$MAC2_IP" config/mac3-backends/enable_firewall.sh \
    && echo "  [OK] firewall allows only the edge $MAC2_IP" || { echo "  [FAIL] enable_firewall.sh default edge is not $MAC2_IP"; bad=1; }
  if [ -n "${OLD_IPS:-}" ]; then
    for o in $OLD_IPS; do
      # shellcheck disable=SC2086
      left=$(grep -l -F "$o" $FILES 2>/dev/null)
      [ -z "$left" ] && echo "  [OK] old IP $o no longer used in Phase 2 files" || { echo "  [FAIL] old IP $o still in: $left"; bad=1; }
    done
  fi
  return $bad
}

if [ "${1:-}" = "--check" ]; then check; exit $?; fi
[ $# -eq 3 ] || { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
N1=$1; N2=$2; N3=$3
for ip in "$N1" "$N2" "$N3"; do in_subnet "$ip" || { echo "$ip is not inside 10.7.0.0/19 - refusing."; exit 1; }; done
[ "$N1" != "$N2" ] && [ "$N1" != "$N3" ] && [ "$N2" != "$N3" ] || { echo "The three IPs must be different."; exit 1; }

O1=$MAC1_IP; O2=$MAC2_IP; O3=$MAC3_IP
echo "Mac 1: $O1 -> $N1    Mac 2: $O2 -> $N2    Mac 3: $O3 -> $N3"
esc() { echo "$1" | sed 's/\./\\./g'; }
# two-step replace via placeholders, so swapping IPs between Macs can never collide
for f in $FILES; do
  [ -f "$f" ] || continue
  sed -i '' -E -e "s/(^|[^0-9.])$(esc "$O1")([^0-9]|\$)/\1@@MAC1@@\2/g" \
               -e "s/(^|[^0-9.])$(esc "$O2")([^0-9]|\$)/\1@@MAC2@@\2/g" \
               -e "s/(^|[^0-9.])$(esc "$O3")([^0-9]|\$)/\1@@MAC3@@\2/g" "$f"
  sed -i '' -e "s/@@MAC1@@/$N1/g" -e "s/@@MAC2@@/$N2/g" -e "s/@@MAC3@@/$N3/g" "$f"
done
. "$P2/lan.env"
OLD_IPS=""; for o in "$O1" "$O2" "$O3"; do case " $N1 $N2 $N3 " in *" $o "*) ;; *) OLD_IPS="$OLD_IPS $o";; esac; done
check || { echo "Check FAILED - fix the lines above."; exit 1; }
"$P2/build_dist.sh"
echo
echo "Next: regenerate the PDF run-sheet and send the new zips + PDF to the team:"
echo "  \"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome\" --headless=new --no-pdf-header-footer \\"
echo "     --print-to-pdf=\"$REPO/dist/Phase2_LAN_Runsheet.pdf\" \"file://$REPO/docs/Phase2_LAN_Runsheet.html\""
echo "On Mac 2 re-install the edge config: ./scripts/phase2/edge_phase2_install.sh install"
