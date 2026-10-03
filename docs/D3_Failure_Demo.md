# D3 — Failure demonstration: Option A (stop one backend)

Fill in the `[ ]` placeholders after recording. Save screenshots in `evidence/failures/3-one-backend-stopped/`.

## Run order (all three Macs; record the screen of Mac 1, plus Mac 2 and Mac 3 when they act)

**Setup (before recording):** check IPs on all Macs with `ipconfig getifaddr en0`. Then:
- Mac 1: `sudo brew services restart dnsmasq`
- Mac 3: start both backends
- Mac 2: start nginx

| Step | Mac | Command / action | What you should see |
|---|---|---|---|
| 0 | Mac 2 | `tail -f /opt/homebrew/var/log/nginx/team1_access.log` (window 1) and `tail -f /opt/homebrew/var/log/nginx/error.log` (window 2) | logs streaming |
| 1 BEFORE | Mac 1 | `for i in 1 2 3 4 5 6; do curl -s -i https://app.team1.test/api/status \| grep -i x-backend; done` | `x-backend: A`, `B`, `A`, `B`, `A`, `B` · access log alternates `:3001` / `:3002` |
| 2 BREAK | Mac 3 | Click the **Backend A** Terminal window and press **Ctrl+C** | `stopped` |
| 3 | Mac 3 | `lsof -nP -iTCP -sTCP:LISTEN \| grep -E ":3001\|:3002"` | only `*:3002` is listed |
| 4 AFTER | Mac 1 | Run the same loop again | every line is `x-backend: B`, and no errors |
| 5 | Mac 2 | Look at the error.log window | `connect() failed (61: Connection refused) while connecting to upstream … upstream: "http://10.7.7.111:3001/api/status"` |
| 6 | Mac 2 | `curl -i http://10.7.7.111:3001/api/status` then `ping -c 2 10.7.7.111` | curl: `Failed to connect … Connection refused` · ping: replies arrive (host is up, only the process is gone) |
| 7 RESTORE | Mac 3 | In the same window: `python3 backend.py A 3001` | `Backend A listening on 0.0.0.0:3001` |
| 8 | Mac 1 | Wait about 10 s (nginx `fail_timeout=10s`), then run the loop again | `A, B, A, B, A, B` again |

## Answer for the form

**(1) Option:** A. Stop one backend (Backend A, port 3001 on Mac 3).

**(2) Before state:** Six requests from Mac 1 to `https://app.team1.test/api/status` returned `X-Backend: A, B, A, B, A, B`. The nginx access log on Mac 2 showed the upstream alternating between `10.7.7.111:3001` and `10.7.7.111:3002`. Evidence: [screenshot names].

**(3) After state:** We stopped the Backend A process with Ctrl+C on Mac 3. The same loop then returned `X-Backend: B` for every request, all with HTTP 200, so users saw no errors. The nginx error.log showed `connect() failed (61: Connection refused) … upstream: "http://10.7.7.111:3001/…"`. From Mac 2, `curl http://10.7.7.111:3001` was refused, while `ping 10.7.7.111` still got replies. Evidence: [screenshot names, time].

**(4) Layer affected and why:** The failure is at the **application layer, on the backend side**. The Backend A process stopped, so nothing was listening on TCP port 3001. The lower layers were all still working:
- DNS still resolved `app.team1.test` to 10.7.16.45.
- The client's TCP + TLS connection to nginx on 443 still succeeded.
- Mac 3 still answered ping (the IP layer was fine).

Only the edge→backend TCP connection to port 3001 failed: Mac 3's operating system answered with a TCP RST (connection refused). Our nginx config has a passive health check (`max_fails=1 fail_timeout=10s`) plus `proxy_next_upstream error timeout`. nginx therefore retried the failed request on Backend B, marked A as down for 10 s, and sent all traffic to B. The client cannot tell anything happened, because it only ever talks to the edge.

**(5) Restore:** We restarted Backend A on Mac 3 with `python3 backend.py A 3001`. After nginx's 10-second `fail_timeout` expired, nginx tried A again, it succeeded, and the loop alternated `A, B, A, B` again. Evidence: [screenshot name].
