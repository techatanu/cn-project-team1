#!/bin/bash
# Mode 1: start the whole team1 stack on this Mac and LEAVE IT RUNNING (for inject_fault.sh,
# diagnose.sh, manual curl/dig demos, screen recordings). Stop with ./sim_down.sh
#   backends 127.0.0.1:3001/3002 | edge https://app.team1.test:8443 (127.0.0.1)
#   primary DNS 127.0.0.1:5300 | backup DNS :5301 | client cache :5302
. "$(dirname "$0")/lib.sh"
if ! sim_up; then
  echo "start failed - see $SIM/*.log / *.out"
  sim_down          # only cleans up if WE took the lock; never touches another test's stack
  exit 1
fi
echo persistent >"$SIM/lock/pid"
cat <<MSG
team1 stack is running (Mode 1). Try:
  dig @127.0.0.1 -p $CLIENT_DNS_PORT app.team1.test
  curl -v --resolve app.team1.test:8443:127.0.0.1 --cacert config/mac2-edge/tls/team1-ca.crt https://app.team1.test:8443/api/status
  ./scripts/phase2/diagnose.sh
  ./scripts/phase2/inject_fault.sh dns-wrong-ip | tcp-port-blocked | tls-cert-mismatch | restore
Stop: ./scripts/phase2/sim_down.sh
MSG
