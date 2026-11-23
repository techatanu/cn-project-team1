# Extension F: Troubleshooting guide (faculty-injected fault)

During the evaluation the faculty injects **one** configuration fault. The spec (section 7.1, Ext F) asks us to *identify the affected layer, isolate or fix it, and explain our reasoning out loud*, checking in this order: **name resolution → TCP connectivity → TLS → application**.

Rule: **never skip a layer.** Each layer depends on the one below it, so the first failing layer is where the fault is. Everything above it is only a symptom.

```
 client ──① DNS──▶ Mac 1 / Mac 3 dnsmasq      "what IP is app.team1.test?"        → 10.7.16.45
        ──② TCP──▶ Mac 2 :443                 SYN → SYN-ACK → ACK                  → connected
        ──③ TLS──▶ nginx certificate          trusted CA + name app.team1.test     → verified
        ──④ HTTP─▶ nginx → Mac 3 :3001/:3002  GET /api/status                      → 200 + X-Backend
```

Automatic version: **`./scripts/phase2/diagnose.sh`** (LAN: `MODE=lan ./scripts/phase2/diagnose.sh`, or `./mac1.sh diagnose` on Mac 1). It runs the four checks in order, stops at the first failure, prints a verdict and the commands to confirm and fix it. Its exit code is the failing layer (0 = healthy, 1 DNS, 2 TCP, 3 TLS, 4 HTTP).
Use it to *confirm*, but in the viva **type the manual commands below and say what each result means.**

---

## Layer 1: DNS (name → IP)

```bash
dig app.team1.test                          # uses this Mac's resolver list
dig @10.7.23.243 app.team1.test             # ask the primary directly
dig @10.7.24.9  app.team1.test             # ask the backup directly
scutil --dns | grep nameserver              # which servers does this Mac use?
dscacheutil -q host -a name app.team1.test  # what the OS cache (browser, curl) is using
```

| You see | Meaning | Fix |
|---|---|---|
| `status: NOERROR`, `A 10.7.16.45`, `SERVER: 10.7.23.243#53` | DNS OK, go to layer 2 | n/a |
| A record **≠ 10.7.16.45** | wrong record (e.g. `dns-wrong-ip`) | on the DNS Mac: `cat /opt/homebrew/etc/team1.hosts`, then `./mac1.sh dns-set 10.7.16.45` (Mac 3: `./mac3.sh dns-set …`), then flush the client: `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder` |
| `connection timed out; no servers could be reached` | the DNS server is down or unreachable | `sudo brew services list \| grep dnsmasq`, `sudo lsof -nP -i :53`, `sudo brew services restart dnsmasq` |
| `status: NXDOMAIN` | name missing or the client uses the wrong server (e.g. 8.8.8.8) | `scutil --dns`; `sudo networksetup -setdnsservers Wi-Fi 10.7.23.243 10.7.24.9` |
| `dig` is right but the browser is wrong | stale OS cache (TTL 30 s) | flush the cache, or wait 30 s |

Say: *"DNS only turns the name into an IP. If this fails, the client never even opens a TCP connection."*

## Layer 2: TCP (can we reach the port?)

```bash
nc -vz -G 3 10.7.16.45 443                  # TCP handshake only
curl -v --connect-timeout 3 http://10.7.16.45:443/   # exit 7 = refused, exit 28 = timeout
ping -c 3 10.7.16.45                        # is the host on the LAN at all?
```

| You see | Meaning | Fix |
|---|---|---|
| `succeeded!` | handshake complete, go to layer 3 | n/a |
| `Connection refused` (curl exit **7**) | host up, it sent a **RST**: nothing listens on 443 | on Mac 2: `lsof -nP -iTCP:443 -sTCP:LISTEN`; `nginx -t && nginx`; check the `listen` line |
| `Operation timed out` (curl exit **28**) | SYNs get **no answer**: a firewall drops them (or the host is down) | `ping`; on Mac 2: `sudo pfctl -s info`, `sudo pfctl -sr`, `sudo pfctl -a com.apple/team1-fault -sr`; remove the rule |
| wrong port in the URL | (Phase 1 failure 5) | use 443 / 8443 as configured |

Wireshark filter `tcp.port==443`: **SYN, SYN, SYN** retransmissions = drop; **SYN → RST** = refused.

Say: *"Refused and timeout are different. Refused means the machine answered and nothing is listening. Timeout means something in the path is silently dropping packets."*

## Layer 3: TLS (is it really app.team1.test, and do we trust it?)

```bash
curl -v https://app.team1.test/ 2>&1 | grep -E 'SSL|subject|issuer|expire|alt'   # never -k
openssl s_client -connect 10.7.16.45:443 -servername app.team1.test </dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

| You see | Meaning | Fix |
|---|---|---|
| `SSL certificate verify ok`, subject `CN=app.team1.test`, issuer `Team1 Local CA` | TLS OK, go to layer 4 | n/a |
| `SSL: no alternative certificate subject name matches target host name` (curl exit **60**) | **name mismatch**: wrong cert loaded (e.g. `tls-cert-mismatch`, SAN = wrong.team1.test) | on Mac 2: `grep ssl_certificate /opt/homebrew/etc/nginx/servers/*.conf`; point it back to `app.team1.test.crt/.key`; `nginx -t && nginx -s reload` |
| `unable to get local issuer certificate` / `self signed certificate` (exit 60) | client does not trust the issuer | install the CA: `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain team1-ca.crt` |
| `certificate has expired` | dates wrong / clock skew | `openssl x509 -noout -dates`; check `date` on both Macs |
| handshake failure (exit 35) | protocol/cipher/key problem | `nginx -t`; check `ssl_protocols`, that key and cert belong together |

Say: *"TCP worked, so the edge is reachable. TLS fails because the certificate doesn't prove it's app.team1.test. We fix the server config instead of using `-k`."*

## Layer 4: HTTP / application (does the service answer?)

```bash
curl -i https://app.team1.test/api/status                  # status line + X-Backend + X-Edge
tail -n 5 /opt/homebrew/var/log/nginx/error.log            # Mac 2: why did the upstream fail?
tail -n 5 /opt/homebrew/var/log/nginx/team1_access.log     # Mac 2: $upstream_addr, up_status
curl -m 3 http://10.7.24.9:3001/api/status                # Mac 2 → backend A directly
curl -m 3 http://10.7.24.9:3002/api/status                # Mac 2 → backend B directly
./mac3.sh status                                           # Mac 3
```

| You see | Meaning | Fix |
|---|---|---|
| `200`, `X-Backend: A/B` | all layers healthy | n/a |
| **502** Bad Gateway, error.log `connect() failed (61: Connection refused)` | backends not running (or wrong upstream port) | Mac 3: `./mac3.sh start`; check the `upstream` block |
| **504** Gateway Timeout, error.log `upstream timed out` | edge cannot reach the backends: firewall drop (e.g. `tcp-port-blocked backend`, or pf on Mac 3 without the edge allowed) | Mac 2: `sudo pfctl -a com.apple/team1-fault -sr`; Mac 3: `sudo pfctl -a com.apple/team1 -sr` (the edge must be 10.7.16.45) |
| 502 for about 5 s right after the backends come back | nginx `fail_timeout=5s` penalty | wait 5 s (expected behaviour) |
| 404 | wrong path / location | check the URL and the nginx `location` |

Diagnostic Conclusion: *"DNS, TCP and TLS all worked, so the problem is behind the edge. A 502 or 504 is nginx telling us the upstream failed."*

---

## Fault Verification: Testing Faults Locally

Mode 1 (this Mac, no other laptops):
```bash
./scripts/phase2/sim_up.sh                                   # long-running local stack
./scripts/phase2/inject_fault.sh dns-wrong-ip                # → diagnose.sh says DNS (1)
./scripts/phase2/inject_fault.sh tls-cert-mismatch           # → TLS (3)
./scripts/phase2/inject_fault.sh tcp-port-blocked edge       # → TCP (2)   sudo
./scripts/phase2/inject_fault.sh tcp-port-blocked backend    # → HTTP 504/502 (4)   sudo
./scripts/phase2/diagnose.sh
./scripts/phase2/inject_fault.sh restore
./scripts/phase2/sim_down.sh
./scripts/phase2/test_extF_faults.sh                         # all of the above, automatically
```
LAN: `MODE=lan ./scripts/phase2/inject_fault.sh dns-wrong-ip` on **Mac 1**; the TCP/TLS faults on **Mac 2**. Diagnose from Mac 1 with `./mac1.sh diagnose`. Restore with `inject_fault.sh restore` on the same Mac.

| Fault | Layer | Typical symptom at the client |
|---|---|---|
| `dns-wrong-ip` | DNS | `dig` → 10.7.31.250; curl times out connecting to the wrong IP |
| `tcp-port-blocked edge` | TCP | handshake times out (exit 28), no TLS at all |
| `tls-cert-mismatch` | TLS | curl exit 60 "no alternative certificate subject name matches" |
| `tcp-port-blocked backend` | HTTP (behind the edge) | 504 Gateway Timeout, then 502 while both backends are marked failed |
| (Phase 1) backends stopped | HTTP | 502 Bad Gateway |
| (Phase 1) wrong DNS server | DNS | NXDOMAIN / timeout from `dig` |

**Wrong-IP trap:** with `dns-wrong-ip`, curl also *times out*, which looks like a TCP problem. Layer 1 catches it first: the IP itself is wrong. This is why we always start with DNS.
