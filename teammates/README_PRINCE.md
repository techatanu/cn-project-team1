# Mac 1 run-sheet: Prince (Phase 2)

Mac 1 (10.7.23.243) is the **primary DNS** and the **test client**. In Phase 2 the client-side tests run from here. Each test prints PASS/FAIL, pauses and tells you exactly what Atanu (Mac 2) or Sambhav (Mac 3) must do, and saves its output to `evidence/phase2/<ext>/lan_run.txt`.

Everything is driven by **one script, `./mac1.sh`**. Run it from this folder.

| Job | Extension | Command |
|---|---|---|
| Primary DNS (dnsmasq, port 53, **TTL 30** now) | A, B | `./mac1.sh start` / `dns-stop` / `dns-start` |
| Change the DNS record | B, E | `./mac1.sh dns-set <ip>` |
| Client-side tests | A–E | `./mac1.sh test-a` … `test-e` |
| Layer-by-layer diagnosis | F | `./mac1.sh diagnose` |
| Send results to Atanu | all | `./mac1.sh collect` → AirDrop the zip |

---

## 0. One-time setup

```bash
cd ~/Downloads/mac1-prince-dns          # wherever you unzipped it
ifconfig en0 | grep "inet "             # must say 10.7.23.243 (otherwise tell Atanu)
./mac1.sh start                         # installs the Phase 2 dnsmasq config, restarts dnsmasq (sudo)
./mac1.sh client-setup                  # this Mac asks 127.0.0.1 first, then the backup 10.7.24.9
./mac1.sh status                        # all [PASS] once Mac 2 and Mac 3 are up too
```
What changed from Phase 1 in `config/mac1-dns/dnsmasq.conf`:
- `local-ttl=60` became **`local-ttl=30`** (Ext B).
- The two `host-record=` lines moved into **`team1.hosts`** (`addn-hosts=`). A record change is now "edit the file + `killall -HUP dnsmasq`", with no restart; `./mac1.sh dns-set` does exactly that.
- Your old `/opt/homebrew/etc/dnsmasq.conf` is kept as `dnsmasq.conf.before-team1-<date>`.

## 1. Demo order (all three Macs on Rishihood_Learner)

Before you start: Sambhav has run `./mac3.sh start` and Atanu has installed the Phase 2 edge config. Run one test at a time, and use a **second Terminal window** for the `./mac1.sh` commands a test asks you to run.

| # | Command (Mac 1) | What happens / what to film |
|---|---|---|
| A | `./mac1.sh test-a` | Both DNS servers answer. When asked: `./mac1.sh dns-stop` → names still resolve through Mac 3, and HTTPS still works. Then the app failure (Sambhav stops the backends → HTTP 502) versus the DNS failure (both DNS servers stopped → "Could not resolve host"). At the end: `./mac1.sh dns-start`. |
| B | `./mac1.sh test-b` | TTL 30 is shown. Sambhav changes the backup when asked; the test changes **your** (primary) record by itself, because 30 s is faster than people can type. The client keeps the **old** cached IP until about 30 s have passed, then switches. Then the change back + manual flush → the new IP **immediately**. |
| C | `./mac1.sh test-c` | Before: `curl http://10.7.24.9:3001` works (bad). Sambhav: `./mac3.sh firewall-on` → your direct curl **times out**, while `https://app.team1.test` still works through the edge. Then `firewall-off`. |
| D | `./mac1.sh test-d` | 5 requests/s through the edge. Sambhav: `./mac3.sh kill-a` → **0 errors**, all `X-Backend: B`. `revive-a` → A and B alternate again. |
| E | `./mac1.sh test-e` | Sambhav: `standby-on`, then `dns-set 10.7.24.9` (backup). The test does the cutover on your primary by itself. Your cached answer still goes to Mac 2 (`X-Edge: primary`) until the TTL runs out, then to Mac 3 (`X-Edge: standby`). Atanu stops nginx on Mac 2 → still 200. Roll back: automatic on your Mac; Sambhav `dns-set 10.7.16.45`. |
| F | `./mac1.sh diagnose` | Checks DNS → TCP → TLS → HTTP and stops at the first broken layer, with the commands to check and fix it. Practise with `./mac1.sh fault-dns` and `./mac1.sh fault-restore`. |

Note: plain `dig` asks the DNS server directly and **bypasses** the macOS cache. To see what the system resolver (browser, curl) is using, check `dscacheutil -q host -a name app.team1.test`. The tests use it for that reason.

## 2. Extension F: what to say while diagnosing (faculty-injected fault)

1. **DNS**: `dig app.team1.test`. Does it answer, and is the answer 10.7.16.45 (the edge)? Check which server answered (`SERVER:` line). A wrong IP or no answer means a DNS-layer fault.
2. **TCP**: `nc -vz 10.7.16.45 443`. "Refused" means nginx isn't listening. "Timeout" means a firewall is dropping packets or the host is down.
3. **TLS**: `curl -v https://app.team1.test/` (never `-k`). Check the certificate subject/SAN against `app.team1.test` and that the issuer is "Team1 Local CA".
4. **HTTP**: a status of 502 or 504 means the edge is fine and the backends are the problem. Look at nginx's `error.log` on Mac 2 and `./mac3.sh status` on Mac 3.

`./mac1.sh diagnose` runs these four steps for you. The full guide is `docs/ExtensionF_Troubleshooting_Guide.md` in the repo.

## 3. Send your results to Atanu, then restore

Each test saves its output to `evidence/phase2/<ext>/lan_run.txt`, and every other `./mac1.sh` command is logged to `evidence/phase2/mac1/session_<date>.txt`. When you are done:
```bash
./mac1.sh collect          # -> team1-mac1-results-<time>.zip (all test outputs, DNS log, client DNS settings)
```
**AirDrop that zip to Atanu.** Then:

```bash
./mac1.sh client-restore      # normal DNS, so the Mac has internet without dnsmasq
./mac1.sh stop
```

## Practice run on your own Mac (optional, no sudo, nothing on port 53)

```bash
DNS_PORT=5300 ./mac1.sh start
DNS_PORT=5300 ./mac1.sh dns-set 10.7.24.9
DNS_PORT=5300 ./mac1.sh status
DNS_PORT=5300 ./mac1.sh stop
```

## Viva points for Mac 1

- **Why two DNS servers?** DNS was a single point of failure. With a backup listed, the client retries the next server after a short timeout.
- **TTL:** our answers carry TTL 30, so clients may reuse an answer for 30 s. A record change reaches a client up to 30 s later unless its cache is flushed. Production migrations lower the TTL first.
- **DNS failure vs app failure:** no IP means no TCP connection at all (`curl: (6)`). With a correct IP but dead backends, TCP and TLS work and nginx returns 502.
