# Mac 3 run-sheet: Sambhav (Phase 2)

Mac 3 (10.7.24.9) has four jobs in Phase 2:

| Job | Extension | Port | Command |
|---|---|---|---|
| Backend A + Backend B (same as Phase 1) | D: HA failover | TCP 3001, 3002 | `./mac3.sh start` / `kill-a` / `revive-a` |
| **Backup DNS** (dnsmasq, same records as Mac 1) | A: backup DNS, B: TTL | UDP/TCP 53 | `./mac3.sh start` / `dns-stop` / `dns-set <ip>` |
| **Firewall** (pf): only Mac 2 may reach 3001/3002 | C: service isolation | n/a | `./mac3.sh firewall-on` / `firewall-off` |
| **Standby edge** (nginx, same config as Mac 2) | E: edge migration | TCP 443 | `./mac3.sh standby-on` / `standby-off` |
| Send results to Atanu | all | n/a | `./mac3.sh collect` → AirDrop the zip |

Everything is driven by **one script, `./mac3.sh`**. Run it from this folder.

---

## 0. One-time setup (about 10 minutes)

```bash
cd ~/Downloads/mac3-sambhav-backends-backupdns     # wherever you unzipped it
brew install dnsmasq nginx                           # nginx is only needed for Ext E
ifconfig en0 | grep "inet "                          # must say 10.7.24.9
```
If your IP is **not** 10.7.24.9, tell Atanu. The edge config, the DNS records and the firewall all use it.

**TLS key for the standby edge (Ext E only).** Atanu AirDrops you `app.team1.test.key`. Move it into the certs folder:
```bash
mv ~/Downloads/app.team1.test.key config/mac3-standby-edge/certs/
chmod 600 config/mac3-standby-edge/certs/app.team1.test.key
```
The certificate (`app.team1.test.crt`) is already there. **Never** commit or re-share the key.

The team CA must still be trusted on this Mac (done in Phase 1). Check with:
`security find-certificate -c "Team1 Local CA" /Library/Keychains/System.keychain | head -2`

**This Mac's DNS client settings** (primary first, then backup):
```bash
sudo networksetup -setdnsservers Wi-Fi 10.7.23.243 10.7.24.9
```

## 1. Start Mac 3 and self-test

```bash
./mac3.sh start      # Backend A + B in the background, backup DNS on port 53 (asks for your password)
./mac3.sh status     # every line must be [PASS]
```
Expected:
```
  [PASS] Backend A answers on :3001 with X-Backend: A
  [PASS] Backend B answers on :3002 with X-Backend: B
  [PASS] Backends listen on ALL interfaces (not only 127.0.0.1)
  [PASS] Backup DNS answers app.team1.test
        record: app.team1.test. 30 IN A 10.7.16.45
```
`./mac3.sh start` replaces `/opt/homebrew/etc/dnsmasq.conf` with `config/mac3-backup-dns/dnsmasq-backup.conf`. If you already had one, the old copy is kept as `dnsmasq.conf.before-team1-<date>`.

Live backend logs, handy on video: `tail -f .run/backend_A.log` (and `.run/backend_B.log`).

## 2. Demo steps (the client-side test runs on Mac 1 or Mac 2 and tells you when to act)

### Ext A: backup DNS
Prince stops the primary DNS on Mac 1, and clients keep resolving through **your** backup.
Keep this running on Mac 3 to show your server answering:
```bash
tail -f /tmp/dnsmasq-backup.log        # you will see: query[A] app.team1.test from 10.7.x.x
```
For the app-failure versus DNS-failure contrast, the test asks you to run `./mac3.sh backends-stop`, then `./mac3.sh backends-start` and `./mac3.sh dns-stop`. Afterwards run `./mac3.sh dns-start`.

### Ext B and Ext E: change the DNS record
When asked, run **the same IP that Prince uses** on Mac 1:
```bash
./mac3.sh dns-set 10.7.24.9     # Ext E: point app.team1.test at the standby edge (this Mac)
./mac3.sh dns-set 10.7.16.45     # roll back to the primary edge (Mac 2)
```
This edits `/opt/homebrew/etc/team1.hosts` and sends SIGHUP to dnsmasq (no restart).

### Ext C: firewall (pf)
```bash
./mac3.sh firewall-on     # saves a rollback copy to ~/team1-pf-backup/, then loads the rules
```
- On Mac 1: `curl -m 3 http://10.7.24.9:3001/api/status` → **times out** (blocked).
- On Mac 2: the same command → **200** (the edge is allowed). `https://app.team1.test` keeps working.

Then roll back:
```bash
./mac3.sh firewall-off    # removes the rules, releases pf, checks the original rules are back
```
The rules are in `config/mac3-backends/pf_team1.conf`, loaded into the anchor `com.apple/team1`. `/etc/pf.conf` is never edited. If anything ever looks wrong, `./mac3.sh firewall-off` is always safe to run.

### Ext D: HA failover
A client Mac sends continuous traffic. When asked:
```bash
./mac3.sh kill-a          # Backend A dies, all traffic must go to B with 0 errors
./mac3.sh revive-a        # A is back, round-robin resumes after about 5 s (nginx fail_timeout=5s)
```

### Ext E: standby edge
```bash
./mac3.sh standby-on      # nginx on :443, same config as Mac 2 but X-Edge: standby
./mac3.sh status          # adds: [PASS] Standby edge on :443 returns 200 with X-Edge: standby
```
Then, when asked, `./mac3.sh dns-set 10.7.24.9` (your backup; the test changes Mac 1 itself). Clients that cached the old answer keep hitting Mac 2 for up to 30 s (TTL), then move to you. Watch them arrive:
`tail -f .run/standby-edge/access.log`. Afterwards: `./mac3.sh dns-set 10.7.16.45` and `./mac3.sh standby-off`.

## 3. Send your results to Atanu, then shut down

Every `./mac3.sh` command is also logged to `evidence/phase2/mac3/session_<date>.txt`. When the demo or recording is done:
```bash
./mac3.sh collect          # -> team1-mac3-results-<time>.zip (status, logs, pf rules + rollback copy, DNS log)
```
**AirDrop that zip to Atanu** before you shut anything down.

```bash
./mac3.sh stop                                   # standby edge, backends, backup DNS, firewall off
sudo networksetup -setdnsservers Wi-Fi empty     # normal internet DNS again after the project
```

## Practice run on your own Mac first (optional, no sudo, nothing on port 53/443)

```bash
DNS_PORT=5301 EDGE_PORT=9443 ./mac3.sh start
DNS_PORT=5301 EDGE_PORT=9443 ./mac3.sh standby-on
DNS_PORT=5301 EDGE_PORT=9443 ./mac3.sh status
DNS_PORT=5301 EDGE_PORT=9443 ./mac3.sh stop
```

## Viva points for Mac 3

- **Backup DNS vs app failure:** if DNS is down, the name never becomes an IP, so no TCP connection is made (`curl: (6) Could not resolve host`). If only the backends are down, DNS, TCP and TLS all work, but nginx answers 502.
- **Firewall drop vs reject:** our pf rule uses `block drop`, so a blocked client sees a **timeout** (curl exit 28). "Connection refused" (exit 7) means the host is reachable but nothing listens on that port.
- **Why the standby edge uses 127.0.0.1 for the backends:** the backends are on the same Mac. Loopback traffic never crosses Wi-Fi (en0), so the pf rules, which filter only en0, don't block it.
- **Remaining single points of failure:** the edge on Mac 2, and **Mac 3 itself**, which hosts both backends, the backup DNS and the standby edge.
