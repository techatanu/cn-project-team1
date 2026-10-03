# D3 — Failure demonstration: Option A (stop one backend) ✅ recorded 3 Oct 2026

Evidence: [`evidence/failures/3-one-backend-stopped`](../evidence/failures/3-one-backend-stopped)
(`option_A_terminal_outputs.pdf`, `option_A_outputs.txt` with the matching nginx log lines from Mac 2).

## Answer for the form (copy-paste)

**(1) Which option:** Option A. We stopped one backend: Backend A, the Python process on port 3001 on Mac 3 (10.7.7.111).

**(2) Before state, with evidence:** At 11:12:40 IST, Mac 1 ran six requests to `https://app.team1.test/api/status`. They returned `X-Backend: A, A, B, A, B, A`, so both backends were serving. The nginx access log on Mac 2 shows the same order: upstream `10.7.7.111:3001, 3001, 3002, 3001, 3002, 3001`. On Mac 3, `lsof` showed both `*:3001` and `*:3002` listening.

**(3) After state, with evidence:** We pressed Ctrl+C on Backend A on Mac 3. After that, `lsof` showed only `*:3002 (LISTEN)`.
- At 11:14:40–41 the same loop returned `X-Backend: B` six times, all HTTP 200, so users saw no errors.
- The nginx error.log on Mac 2 recorded `connect() failed (61: Connection refused) while connecting to upstream … upstream: "http://10.7.7.111:3001/api/status"`.
- The access log shows `10.7.7.111:3001, 10.7.7.111:3002 … 200`: nginx tried A, was refused, and retried the same request on B.
- From Mac 2, `curl http://10.7.7.111:3001/api/status` failed with `Failed to connect to 10.7.7.111 port 3001 … Couldn't connect to server`.
- But `ping -c 2 10.7.7.111` got 2 of 2 replies (0 % loss).

**(4) Layer affected and why:** The failure is at the **application layer, on the backend side**. The Backend A process stopped, so nothing listened on TCP port 3001 anymore. The lower layers all kept working:
- DNS still resolved `app.team1.test` to 10.7.16.45.
- The client's TCP + TLS connection to nginx on 443 still worked.
- Mac 3 still answered ping, so the network/IP layer was fine.

Only nginx's TCP connection to port 3001 was refused: Mac 3 sent a TCP RST, error 61. The client never noticed, because it only talks to the edge. Our nginx config uses a passive health check (`max_fails=1 fail_timeout=10s`) plus `proxy_next_upstream error timeout`. nginx therefore retried the failed request on Backend B, marked A as down, and sent all traffic to B.

**(5) How we restored the system:** On Mac 3 we ran `python3 backend.py A 3001` again, and it printed `Backend A listening on 0.0.0.0:3001`. Its log immediately showed requests from nginx (`10.7.16.45 … "GET /api/status HTTP/1.1" 200`). At 11:17:51 the loop on Mac 1 returned `X-Backend: B, B, A, B, A, B`, and the access log shows `3002, 3002, 3001, 3002, 3001, 3002`. Both backends are back in the rotation.

## Run sheet (for re-recording the video)

| Step | Mac | Command / action | What you should see |
|---|---|---|---|
| 0 | Mac 2 | `tail -n 0 -f /opt/homebrew/var/log/nginx/team1_access.log` and `tail -n 0 -f /opt/homebrew/var/log/nginx/error.log` (`-n 0` hides old lines) | empty windows that fill as requests arrive |
| 1 Before | Mac 1 | `for i in 1 2 3 4 5 6; do curl -s -i https://app.team1.test/api/status \| grep -i x-backend; done` | a mix of A and B · access log shows `:3001` and `:3002` |
| 2 Break | Mac 3 | Press Ctrl+C in the Backend A window | `stopped` |
| 3 | Mac 3 | `lsof -nP -iTCP -sTCP:LISTEN \| grep -E ":3001\|:3002"` | only `*:3002` |
| 4 After | Mac 1 | Run the same loop again | all `B` |
| 5 | Mac 2 | Look at the error.log window | `connect() failed (61: Connection refused) … 10.7.7.111:3001` |
| 6 | Mac 2 | `curl -i http://10.7.7.111:3001/api/status` then `ping -c 2 10.7.7.111` | curl fails, ping gets replies |
| 7 Restore | Mac 3 | `python3 backend.py A 3001` | `Backend A listening on 0.0.0.0:3001` |
| 8 | Mac 1 | Run the loop again | A and B both appear again |
