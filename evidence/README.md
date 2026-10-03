# Evidence index

`pNN_*.png` files are pages of our recorded chat/evidence log (`Cn_Chat.pdf`, 2 Oct 2026); `mac2_*` files were
exported directly from Mac 2. `optional_screenshots_3oct.pdf` holds the original terminal outputs, from all three Macs, for the 3 Oct re-checks. Status: ✅ present · ⬜ still to add.

| Folder | Task | Present | Still to add |
|---|---|---|---|
| [A-ping](A-ping) | A – LAN | networksetup (IP/mask/router/MAC) for all 3 Macs; all 6 directed pings, 0 % loss | — |
| [B-dns](B-dns) | B – DNS | `dig app/api.team1.test` from Mac 2 & 3 → 10.7.16.45 via 10.7.28.177; Mac 2 `dig @8.8.8.8` NXDOMAIN; Mac 1 `lsof :53`; client DNS settings (in A-ping/p05) | (optional) `sudo tail -20 /tmp/dnsmasq.log` on Mac 1 |
| [C-backends](C-backends) | C – Backends | Backend A/B logs; Mac 3 `lsof *:3001/*:3002` + local curl; Mac 2 curl to 10.7.7.111:3001 and :3002 | — |
| [D-loadbalancing](D-loadbalancing) | D – LB | full nginx access log (`$remote_addr -> $upstream_addr`); A/B loops (in failures/3-one-backend-stopped) | — |
| [E-tls](E-tls) | E – TLS | `openssl verify` OK; CA trust; `curl -v` TLS 1.2 & 1.3 verify ok; browser Certificate Viewer; `--http1.1` vs `--http2` | — |
| [F-caching](F-caching) | F – Caching | `curl -I` cache headers + ETag; 304 from A and B; DevTools 304 and `(disk cache)`; log 200/304 | — |
| [G-capture](G-capture) | G – Capture | `phase1_full_flow.pcapng` + tshark summary; DNS (pkt 240 TTL 60 screenshot), TCP, TLS 1.2/1.3, Certificate, encrypted data, plain-HTTP edge→backend, Conversations | — |
| [failures](failures) | 6.3 / form D3 | ✅ **Option A, one backend stopped** (3 Oct 2026): before/after loops, lsof, nginx error + access log, curl refused, ping OK, restore. Also the accidental wrong-record `dig` (10.7.7.111) and `mac2_nginx_error.log` | the other four scenarios are optional (procedure in report 7.2) |
