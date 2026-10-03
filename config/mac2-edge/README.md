# Mac 2 — Edge: nginx reverse proxy, TLS termination, load balancer (Atanu, 10.7.16.45)

nginx 1.31.6 (Homebrew). Homebrew's main `nginx.conf` already has `include servers/*;`, so our
server block lives in `/opt/homebrew/etc/nginx/servers/team1.conf` → copy: [`nginx/team1.conf`](nginx/team1.conf).

Key choices:
- `listen 443 ssl; http2 on;` — port 443 bound without sudo; HTTP/2 + HTTP/1.1 via ALPN.
- `ssl_protocols TLSv1.2 TLSv1.3;`
- `upstream team1_backends` — default **round-robin** across `10.7.7.111:3001` (A) and `:3002` (B).
- Passive health check: `max_fails=1 fail_timeout=10s` + `proxy_next_upstream error timeout http_502 http_503`
  + `proxy_connect_timeout 2s` → a dead backend is skipped for 10 s and the request is retried on the other.
- Custom `log_format team1` logs `$upstream_addr`, proving which backend served each request.
- Edge → backend traffic is plain HTTP (TLS terminates at nginx).

```bash
nginx -t            # syntax is ok / test is successful
nginx               # start      | nginx -s reload  (after edits) | nginx -s stop
lsof -nP -iTCP:443 -sTCP:LISTEN
tail -f /opt/homebrew/var/log/nginx/team1_access.log
tail -n 5 /opt/homebrew/var/log/nginx/error.log
```

TLS certificate setup: see [`tls/README.md`](tls/README.md).
