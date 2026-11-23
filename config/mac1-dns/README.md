# Mac 1 — Private DNS (Prince, 10.7.23.243)

dnsmasq 2.93 (Homebrew). Config path: `/opt/homebrew/etc/dnsmasq.conf` → copy here: [`dnsmasq.conf`](dnsmasq.conf).

| Line | Why |
|---|---|
| `interface=en0`, `listen-address=127.0.0.1` | answer LAN clients on Wi-Fi and Mac 1 itself |
| `domain-needed`, `bogus-priv` | don't forward plain names / private reverse lookups upstream |
| `local=/team1.test/` | dnsmasq is authoritative for `team1.test`; never forwards it |
| `addn-hosts=/opt/homebrew/etc/team1.hosts` | **Phase 2:** A records (app/api → 10.7.16.45, the edge) live in [`team1.hosts`](team1.hosts); change = edit + `killall -HUP dnsmasq`, no restart ([`set_record.sh`](set_record.sh)). Phase 1 used `host-record=` lines. |
| `local-ttl=30` | **Phase 2 (Ext B):** answers carry TTL 30 s (Phase 1: 60) |
| `no-resolv` + `server=8.8.8.8`, `server=1.1.1.1` | other names are forwarded so clients keep internet; avoids a resolver loop |
| `log-queries`, `log-facility=/tmp/dnsmasq.log` | query log as evidence |

## Commands (Mac 1)

```bash
dnsmasq --test                        # syntax check OK
sudo brew services restart dnsmasq    # required after EVERY edit (start does nothing if already running)
sudo lsof -nP -i :53                  # listening on 10.7.23.243:53 and 127.0.0.1:53, UDP + TCP
dig @127.0.0.1 app.team1.test         # 30 IN A 10.7.16.45
tail -f /tmp/dnsmasq.log
```

## Client resolver setup

```bash
# Phase 2 (Ext A): primary first, then the backup DNS on Mac 3
sudo networksetup -setdnsservers Wi-Fi 127.0.0.1 10.7.24.9     # Mac 1 (uses itself, then backup)
sudo networksetup -setdnsservers Wi-Fi 10.7.23.243 10.7.24.9   # Mac 2 and Mac 3
networksetup -getdnsservers Wi-Fi
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
dig app.team1.test                                      # must show SERVER: 10.7.23.243#53
```

Search Domains must stay empty. After the project, restore normal DNS on Mac 2/3:
`sudo networksetup -setdnsservers Wi-Fi empty` (otherwise they lose internet when Mac 1 is off).

Phase 2 backup DNS (same records + TTL) runs on Mac 3: [`../mac3-backup-dns/dnsmasq-backup.conf`](../mac3-backup-dns/dnsmasq-backup.conf).
