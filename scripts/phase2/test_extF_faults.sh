#!/bin/bash
# Extension F self-test: inject each fault, check that diagnose.sh blames the RIGHT layer, restore.
#   healthy -> 0 | dns-wrong-ip -> DNS (1) | tcp-port-blocked edge -> TCP (2)
#   tls-cert-mismatch -> TLS (3) | tcp-port-blocked backend -> HTTP 502/504 (4)
# The two pf faults need sudo: run in Terminal.app for the full test. Without a terminal
# (e.g. a non-interactive or sandboxed shell) they are SKIPPED and the DNS + TLS faults still run.
# Mode 1 only (in the LAN the faculty injects the fault; use inject_fault.sh / diagnose.sh by hand).
. "$(dirname "$0")/lib.sh"
start_evidence extF "$@"
[ "$MODE" = "local" ] || { echo "test_extF_faults.sh is Mode 1 only. LAN: MODE=lan ./diagnose.sh"; exit 1; }
INJ="$P2_DIR/inject_fault.sh"; DIAG="$P2_DIR/diagnose.sh"
cleanup() { [ -f "$SIM/fault" ] && "$INJ" restore >/dev/null 2>&1; sim_down; }
trap cleanup EXIT

SUDO=""
if sudo -n true 2>/dev/null; then SUDO=1
elif [ -t 0 ] && sudo -v; then SUDO=1; fi

section "Setup (Mode 1): full stack"
sim_up || { fail "could not start the local stack"; summary; exit 1; }

check() { # check <fault-args|healthy> <expected exit> <label>
  local f=$1 want=$2 label=$3 rc
  section "$label"
  if [ "$f" != healthy ]; then "$INJ" $f | sed 's/^/  /'; fi
  "$DIAG" | sed 's/^/  | /'; rc=${PIPESTATUS[0]}
  expect "diagnose.sh stops at layer $want ($label) - got $rc" [ "$rc" = "$want" ]
  if [ "$f" != healthy ]; then
    "$INJ" restore | sed 's/^/  /'
    sleep 6     # nginx fail_timeout=5s after backend faults
    "$DIAG" >/dev/null 2>&1; rc=$?
    expect "after restore all 4 layers are healthy again" [ "$rc" = 0 ]
  fi
}

check healthy 0 "Baseline: healthy system"
check dns-wrong-ip 1 "Fault 1: DNS returns a wrong IP"
check tls-cert-mismatch 3 "Fault 2: TLS certificate name mismatch"
if [ -n "$SUDO" ]; then
  check "tcp-port-blocked edge" 2 "Fault 3: TCP port of the edge blocked (pf drop)"
  check "tcp-port-blocked backend" 4 "Fault 4: backend ports blocked behind the edge (pf drop)"
else
  section "Faults 3 + 4 (pf) SKIPPED: no sudo here. Run this test in Terminal.app for them."
fi
summary
