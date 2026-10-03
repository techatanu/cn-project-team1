# B – DNS
- p08: `dig app.team1.test` (Mac 2, Mac 3) and `dig api.team1.test` (Mac 3) → 10.7.16.45 from SERVER 10.7.28.177#53, TTL 60, flag `aa`.
- mac2_dig_8.8.8.8_nxdomain.txt: public DNS returns NXDOMAIN (3 Oct 11:32 IST).
- mac1_lsof_port53.txt: dnsmasq on UDP+TCP 53 (10.7.28.177, 127.0.0.1, IPv6). Reading `/tmp/dnsmasq.log` needs `sudo`.
