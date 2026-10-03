# Evidence index

`pNN_*.png` files are pages of our recorded chat/evidence log (`Cn_Chat.pdf`, 2 Oct 2026); `mac2_*` files were
exported directly from Mac 2. Status: ✅ present · ⬜ still to add.

| Folder | Task | Present | Still to add |
|---|---|---|---|
| [A-ping](A-ping) | A – LAN | networksetup (IP/mask/router/MAC) for all 3 Macs; all 6 directed pings, 0 % loss | ⬜ (optional) clean screenshot per Mac |
| [B-dns](B-dns) | B – DNS | `dig app.team1.test` from Mac 2 & 3 and `dig api.team1.test` from Mac 3 → 10.7.16.45 via 10.7.28.177; client DNS settings (in A-ping/p05) | ⬜ `dig @8.8.8.8 app.team1.test` NXDOMAIN screenshot; ⬜ Mac 1 `lsof -i :53` + `dnsmasq.log` |
| [C-backends](C-backends) | C – Backends | Backend A and B terminal logs (requests from 127.0.0.1 and 10.7.16.45) | ⬜ local curl + `lsof *:3001/*:3002` screenshot; ⬜ Mac 2 → `curl http://10.7.7.111:3001/3002` |
| [D-loadbalancing](D-loadbalancing) | D – LB | full nginx access log (`$remote_addr -> $upstream_addr`) | ⬜ screenshot of the 6-request A/B loop |
| [E-tls](E-tls) | E – TLS | `openssl verify` OK; CA trust; `curl -v` TLS 1.2 & TLS 1.3 "SSL certificate verify ok" | ⬜ browser padlock / certificate viewer screenshot; ⬜ `--http1.1` vs `--http2` output |
| [F-caching](F-caching) | F – Caching | `curl -I` cache headers + ETag; 304 from A and B; DevTools 304 and `(disk cache)`; log 200/304 | — |
| [G-capture](G-capture) | G – Capture | DNS, SYN/SYN-ACK/ACK, TLS 1.2 & 1.3 handshakes, Certificate packet, encrypted Application Data, plain-HTTP edge→backend stream, TCP/UDP Conversations | ⬜ `phase1_full_flow.pcapng` + `bonus_nginx_backend_not_encrypted.pcapng` files (on Mac 3); ⬜ packet 240 expanded showing TTL 60 |
| [failures](failures) | 6.3 | accidental wrong-record `dig` (10.7.7.111) | ⬜ all five deliberate demos (see each sub-folder) |
