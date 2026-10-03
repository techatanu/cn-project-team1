# Mac 1 — Private DNS (Prince, 10.7.28.177)

dnsmasq 2.93 (Homebrew). Config path: `/opt/homebrew/etc/dnsmasq.conf` → copy here: [`dnsmasq.conf`](dnsmasq.conf).

| Line | Why |
|---|---|
| `interface=en0`, `listen-address=127.0.0.1` | answer LAN clients on Wi-Fi and Mac 1 itself |
| `domain-needed`, `bogus-priv` | don't forward plain names / private reverse lookups upstream |
| `local=/team1.test/` | dnsmasq is authoritative for `team1.test`; never forwards it |
| `host-record=app.team1.test,10.7.16.45` / `api…` | A records → Mac 2 (the edge, never a backend) |
| `local-ttl=60` | answers carry TTL 60 s |
| `no-resolv` + `server=8.8.8.8`, `server=1.1.1.1` | other names are forwarded so clients keep internet; avoids a resolver loop |
| `log-queries`, `log-facility=/tmp/dnsmasq.log` | query log as evidence |

## Commands (Mac 1)

```bash
dnsmasq --test                        # syntax check OK
sudo brew services restart dnsmasq    # required after EVERY edit (start does nothing if already running)
sudo lsof -nP -i :53                  # listening on 10.7.28.177:53 and 127.0.0.1:53, UDP + TCP
dig @127.0.0.1 app.team1.test         # 60 IN A 10.7.16.45
tail -f /tmp/dnsmasq.log
```

## Client resolver setup

```bash
sudo networksetup -setdnsservers Wi-Fi 127.0.0.1        # Mac 1 (uses itself)
sudo networksetup -setdnsservers Wi-Fi 10.7.28.177      # Mac 2 and Mac 3
networksetup -getdnsservers Wi-Fi
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
dig app.team1.test                                      # must show SERVER: 10.7.28.177#53
```

Search Domains must stay empty. After the project, restore normal DNS on Mac 2/3:
`sudo networksetup -setdnsservers Wi-Fi empty` (otherwise they lose internet when Mac 1 is off).
