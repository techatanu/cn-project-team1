# Backends (Mac 3 — Sambhav, 10.7.7.111)

One Python 3 script (standard library only), run as **two processes** on Mac 3.
Our team has 3 members, so the spec's Mac 3 + Mac 4 backend roles are combined on one Mac
(allowed by spec section 3: "Teams of 2–3 may combine machine roles").

| Process | Command | Listens on |
|---|---|---|
| Backend A | `cd ~/cn-project/backend && python3 backend.py A 3001` | `0.0.0.0:3001` |
| Backend B | `cd ~/cn-project/backend && python3 backend.py B 3002` | `0.0.0.0:3002` |

Leave both Terminal windows open. Ctrl+C stops a backend (used in the failure demos).

## Endpoints

| Endpoint | Response | Cache header |
|---|---|---|
| `GET /` | `{"service":"team1 backend","backend":"A","message":"Backend A is running"}` | `no-store` |
| `GET /api/status` | `{"backend":"A","status":"ok","time":"<UTC ISO time>"}` | `no-store` |
| `GET /api/info` | identical JSON on both backends (117 bytes) | `public, max-age=60` + `ETag: "6c623c0954f8001c"`; returns **304** when `If-None-Match` matches |

Every response carries `X-Backend: A` or `X-Backend: B`.
The ETag is a hash of the body, so both backends produce the same ETag and a 304 works even when
round-robin sends the revalidation to the other backend.

## Checks

```bash
# on Mac 3
curl -i http://localhost:3001/api/status
lsof -nP -iTCP -sTCP:LISTEN | grep -E ":3001|:3002"     # must show *:3001 and *:3002 (not 127.0.0.1)
# on Mac 2 (proves LAN reachability)
curl -i http://10.7.7.111:3001/api/status
curl -i http://10.7.7.111:3002/api/status
```

Note: Mac 3 has Anaconda, so plain `curl` there is `/opt/anaconda3/bin/curl`, which does not read the
macOS Keychain. Use `/usr/bin/curl` for HTTPS tests on Mac 3.
