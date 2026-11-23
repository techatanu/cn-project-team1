#!/bin/bash
# Build the teammate packages in dist/ (Mac 3 Sambhav, Mac 1 Prince).   ./build_dist.sh
# Each zip mirrors the repo layout (config/..., backend/...), so the scripts inside find their
# files exactly as they do in the repo. Entries are "repo-path" or "repo-path:path-in-zip".
# Private keys (*.key) are never packaged; the build fails if one slips in.
set -e
P2="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$P2/../.." && pwd)"
DIST="$REPO/dist"; mkdir -p "$DIST"

pack() { # pack <zip-name> <entry>...
  local name=$1; shift
  local tmp; tmp="$(mktemp -d "${TMPDIR:-/tmp}/team1dist.XXXXXX")"
  local stage="$tmp/$name" e src dst
  mkdir -p "$stage"
  for e in "$@"; do
    src="${e%%:*}"; dst="${e#*:}"
    mkdir -p "$stage/$(dirname "$dst")"
    cp -R "$REPO/$src" "$stage/$dst"
  done
  find "$stage" \( -name '*.key' -o -name '.DS_Store' -o -name '.run' \) -prune -exec rm -rf {} +
  find "$stage" -name '*.sh' -exec chmod +x {} +
  rm -f "$DIST/$name.zip"
  (cd "$tmp" && zip -qr "$DIST/$name.zip" "$name")
  rm -rf "$tmp"
  if unzip -l "$DIST/$name.zip" | grep -q '\.key$'; then
    echo "ERROR: a private key ended up in $name.zip" >&2; rm -f "$DIST/$name.zip"; exit 1
  fi
  echo "built dist/$name.zip ($(unzip -l "$DIST/$name.zip" | tail -1 | awk '{print $2}') files, no *.key)"
}

pack mac3-sambhav-backends-backupdns \
  teammates/README_SAMBHAV.md:README_SAMBHAV.md \
  teammates/mac3.sh:mac3.sh \
  backend/backend.py \
  config/mac3-backends \
  config/mac3-backup-dns \
  config/mac3-standby-edge \
  config/mac2-edge/tls/team1-ca.crt \
  config/mac2-edge/nginx/team1-phase2.conf

pack mac1-prince-dns \
  teammates/README_PRINCE.md:README_PRINCE.md \
  teammates/mac1.sh:mac1.sh \
  config/mac1-dns \
  config/mac2-edge/tls/team1-ca.crt \
  scripts/phase2/lib.sh \
  scripts/phase2/lan.env \
  scripts/phase2/test_extA_dns_failover.sh \
  scripts/phase2/test_extB_ttl_cutover.sh \
  scripts/phase2/test_extC_firewall.sh \
  scripts/phase2/test_extD_ha_failover.sh \
  scripts/phase2/test_extE_edge_migration.sh \
  scripts/phase2/diagnose.sh \
  scripts/phase2/inject_fault.sh
