# Phase 1 Demo Video — Script (3 members, about 10 min)

**Speakers:** **PRINCE** (Mac 1, DNS + client) · **ATANU** (Mac 2, nginx edge) · **SAMBHAV** (Mac 3, backends + Wireshark)
The script follows the spec's demo sequence (section 8, steps 1–8) and the section numbers of `Phase1_Report.md`.
`$` lines are typed on screen. *Italics* = what should be visible.

---

## Before you press record (10 min)

1. All three Macs on **Rishihood_Learner**. On every Mac: `ipconfig getifaddr en0`.
   It must be 10.7.28.177 / 10.7.16.45 / 10.7.7.111. If Mac 2 changed → fix dnsmasq. If Mac 3 changed → fix nginx upstream.
2. Mac 1: `sudo brew services restart dnsmasq`
3. Mac 3: two Terminal windows → `python3 backend.py A 3001` and `python3 backend.py B 3002`
4. Mac 2: `nginx -t && nginx` (or `nginx -s reload` if already running). Second window: `tail -n 0 -f /opt/homebrew/var/log/nginx/team1_access.log`. Third window: `tail -n 0 -f /opt/homebrew/var/log/nginx/error.log`
5. Mac 1 and Mac 3: `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`
6. Terminal font size large (Cmd +). Close unrelated tabs. Open `docs/diagrams/topology.png`.
7. **Mac 3 always uses `/usr/bin/curl`**, never plain `curl`.
8. Never use `curl -k` in the video.

---

## Scene 1 — Introduction and topology (ATANU, ~1 min) · demo step 1

*Screen: topology diagram.*

**ATANU:** "Hello, we are Team 1: Prince, Sambhav and me, Atanu. Our project is a private network service platform. It runs completely on our three laptops on the college Wi-Fi, with no cloud.
A client types `app.team1.test`. Our own DNS server on Mac 1 turns that name into the IP of Mac 2. Mac 2 runs nginx. It handles HTTPS and load-balances each request to one of two backends on Mac 3, Backend A on port 3001 and Backend B on port 3002.
We are three members, so the spec allows us to combine roles: both backends run on Mac 3 as two processes.
In cloud terms, Mac 1 is like Route 53, Mac 2 is like an AWS load balancer, and the backends are like EC2 instances."

*Screen: IP table from the report, section 2.*

**ATANU:** "All machines are on 10.7.0.0/19 with gateway 10.7.0.1 on interface en0. Mac 1 is 10.7.28.177, Mac 2 is 10.7.16.45 and Mac 3 is 10.7.7.111."

---

## Scene 2 — LAN check (all three, ~45 s) · demo step 2

**PRINCE** (Mac 1): `$ ipconfig getifaddr en0` → `$ ping -c 2 10.7.16.45` → `$ ping -c 2 10.7.7.111`
**ATANU** (Mac 2): `$ ipconfig getifaddr en0` → `$ ping -c 2 10.7.7.111`
**SAMBHAV** (Mac 3): `$ ipconfig getifaddr en0` → `$ ping -c 2 10.7.28.177`

**PRINCE:** "Every machine can reach every other machine with zero packet loss, so the LAN layer is working. Nothing else can work without this."

---

## Scene 3 — Private DNS (PRINCE, ~1.5 min) · demo step 3

*Mac 1:*
`$ cat /opt/homebrew/etc/dnsmasq.conf`

**PRINCE:** "This is dnsmasq on my Mac. `local=/team1.test/` makes it authoritative for our domain. The two `host-record` lines point `app` and `api` to 10.7.16.45, which is the edge, not a backend. The TTL is 60 seconds. Any other name is forwarded to 8.8.8.8, so we still have internet."

`$ sudo lsof -nP -i :53`
**PRINCE:** "It is listening on port 53, UDP and TCP."

*Mac 3:*
**SAMBHAV:** `$ networksetup -getdnsservers Wi-Fi` → *10.7.28.177*
`$ dig app.team1.test`
**SAMBHAV:** "My Mac uses Prince's Mac as its DNS server. The answer is 10.7.16.45 with TTL 60, and the SERVER line shows 10.7.28.177 port 53."
`$ dig @8.8.8.8 app.team1.test`
**SAMBHAV:** "Google's DNS says NXDOMAIN. This name exists only inside our network."

**PRINCE:** "DNS only finds the IP address. It does not connect to anything. The HTTPS connection comes next, and it is a separate TCP connection."

---

## Scene 4 — Backends (SAMBHAV, ~1 min) · task C

*Mac 3: show the two backend windows.*
**SAMBHAV:** "This is one small Python script running twice, as Backend A on port 3001 and Backend B on port 3002. It has three endpoints: `/`, `/api/status`, and `/api/info` for caching. Every response has an `X-Backend` header, so we can see which backend answered."
`$ lsof -nP -iTCP -sTCP:LISTEN | grep -E ":3001|:3002"`
**SAMBHAV:** "The star means they listen on all interfaces, not only localhost, so Mac 2 can reach them over the LAN."

*Mac 2:*
**ATANU:** `$ curl -i http://10.7.7.111:3001/api/status` → *X-Backend: A* · `$ curl -i http://10.7.7.111:3002/api/status` → *X-Backend: B*

---

## Scene 5 — nginx edge and HTTPS (ATANU, ~2 min) · demo step 4

*Mac 2:*
`$ cat /opt/homebrew/etc/nginx/servers/team1.conf`
**ATANU:** "The `upstream` block lists both backends. Round-robin is nginx's default. `max_fails=1 fail_timeout=10s` and `proxy_next_upstream` give us a passive health check. The server listens on 443 with TLS 1.2 and 1.3 and HTTP/2. TLS terminates here, so traffic from nginx to the backends is plain HTTP inside our LAN."
`$ nginx -t`

**ATANU:** "For the certificate we made our own team CA with OpenSSL and used it to sign a certificate for app.team1.test and api.team1.test. We added the CA to the System keychain on all three Macs. That is why there is no warning, and we never use `curl -k`."
`$ openssl x509 -in ~/cn-project/certs/app.team1.test.crt -noout -subject -issuer -ext subjectAltName`

*Mac 1:*
**PRINCE:** `$ curl -v https://app.team1.test/api/status`
**PRINCE:** "Look at the output: Connected to app.team1.test on 10.7.16.45 port 443, then the TLS handshake, then subjectAltName matched and SSL certificate verify ok. ALPN chose h2, so this is HTTP/2. The response has `x-backend`."
`$ curl -sI --http1.1 https://app.team1.test/` → *HTTP/1.1 200 OK*
`$ curl -sI --http2 https://app.team1.test/` → *HTTP/2 200*
*Then open Chrome at `https://app.team1.test/api/status`, click the padlock and show the certificate.*
**PRINCE:** "In the browser we use only the name, with no IP address, and the padlock shows our certificate."

---

## Scene 6 — Load balancing (PRINCE + ATANU, ~1 min) · demo step 5

*Mac 1:*
`$ for i in 1 2 3 4 5 6; do curl -s -i https://app.team1.test/api/status | grep -i x-backend; done`
**PRINCE:** "Same name and same IP, but the answers come from A and from B. nginx alternates between the backends."

*Mac 2: show the access-log window.*
**ATANU:** "The nginx log confirms it. Each line shows the client IP and the upstream nginx chose, alternating between port 3001 and port 3002. The client never knows the backend addresses. It only knows the edge."

---

## Scene 7 — Caching (PRINCE, ~1.5 min) · demo step 7

*Mac 1:*
`$ curl -I https://app.team1.test/api/info`
**PRINCE:** "This endpoint sends `Cache-Control: public, max-age=60` and an ETag."
`$ ETAG=$(curl -sI https://app.team1.test/api/info | grep -i '^etag' | awk '{print $2}' | tr -d '\r')`
`$ curl -i -H "If-None-Match: $ETAG" https://app.team1.test/api/info` *(run 2–3 times)*
**PRINCE:** "When we send the ETag back, the server answers 304 Not Modified with no body. It works from both A and B because the ETag is a hash of the content, so both backends agree."

*Chrome, DevTools → Network, open `/api/info` and reload.*
**PRINCE:** "Here the browser gets 304 on reload. When it reuses the copy within 60 seconds it shows 'disk cache' in about 1 millisecond, with no request sent at all. That is the difference: a fresh cache hit sends nothing, a conditional request gets a 304 with headers only, and a full request gets a 200 with the body."

---

## Scene 8 — Wireshark evidence (SAMBHAV, ~2.5 min) · demo step 6

*Mac 3: open `phase1_full_flow.pcapng`.*

**SAMBHAV:** "I captured this on Mac 3's Wi-Fi while running curl with TLS 1.2 and then TLS 1.3."

1. Filter `dns.qry.name contains "team1.test"` → click pkt 239, then 240.
   **SAMBHAV:** "Packet 239 is my DNS query, UDP from ephemeral port 50215 to port 53 on Mac 1. Packet 240 is the answer, 10.7.16.45 with TTL 60." *(expand Answers to show TTL)*
2. Filter `tcp.stream eq 0`.
   **SAMBHAV:** "Packet 243 is the SYN from port 59200 to 443, then SYN-ACK and ACK: the three-way handshake. The sequence numbers start at 0, and the ACK number is the next byte expected. The red rows are retransmissions. Our Wi-Fi is busy, so TCP resent the SYN, which shows its reliability."
3. Filter `tcp.stream eq 0 && tls`.
   **SAMBHAV:** "Packet 249 is the Client Hello with SNI app.team1.test. Packet 252 is Server Hello, Certificate and Server Key Exchange. Here you can see our certificate in this TLS 1.2 session. Then Change Cipher Spec, and after that only Application Data."
4. Filter `tls.record.content_type == 23` → click a packet, show hex.
   **SAMBHAV:** "The application data is encrypted. We cannot read the HTTP headers here, even though curl -v showed them."
5. Filter `tcp.stream eq 2 && tls`.
   **SAMBHAV:** "This is the TLS 1.3 connection. The certificate is no longer visible, because TLS 1.3 encrypts it too."
6. Open the bonus capture, filter `tcp.port == 3001`, Follow TCP Stream.
   **SAMBHAV:** "This is nginx talking to Backend A. It is plain readable HTTP: GET /api/status, X-Forwarded-Proto https, X-Backend A. This proves TLS ends at the edge."
7. Statistics → Conversations → TCP.
   **SAMBHAV:** "Six client connections to 443, and six connections from nginx to the backends alternating between 3001 and 3002."

---

## Scene 9 — Failure demonstration: Option A, stop one backend (all, ~2 min) · demo step 8 + form D3

The form asks for **one** failure, and we chose Option A. These are the outputs we recorded on 3 Oct 2026, so the video should show the same thing.
On Mac 2, start the log windows with `tail -n 0 -f …` so old lines don't appear.

**PRINCE** (Mac 1), *before*:
`$ for i in 1 2 3 4 5 6; do curl -s -i https://app.team1.test/api/status | grep -i x-backend; done` → *A A B A B A*
**PRINCE:** "Before the failure, both backends answer. Requests go to A and to B."
**ATANU** (Mac 2): "The access log shows the upstream switching between port 3001 and port 3002."

**SAMBHAV** (Mac 3), *break*: press **Ctrl+C** in the Backend A window → *stopped*
`$ lsof -nP -iTCP -sTCP:LISTEN | grep -E ":3001|:3002"` → *only `*:3002`*
**SAMBHAV:** "I stopped Backend A. Only port 3002 is listening now."

**PRINCE**, *after*: run the same loop → *B B B B B B*
**PRINCE:** "Every response now comes from Backend B, and none of them failed. The user sees no error."

**ATANU** (Mac 2): point at error.log → *connect() failed (61: Connection refused) … upstream: "http://10.7.7.111:3001/api/status"*
**ATANU:** "nginx tried Backend A and got connection refused. In the access log, one line shows two upstreams, 3001 then 3002: nginx retried the same request on B. Because of `max_fails=1` and `fail_timeout=10s`, it stopped sending traffic to A."
`$ curl -i http://10.7.7.111:3001/api/status` → *Failed to connect … Couldn't connect to server*
`$ ping -c 2 10.7.7.111` → *2 packets received, 0% loss*
**ATANU:** "The machine is still reachable. Only the application on port 3001 is gone. So the failed layer is the application layer on the backend. DNS, TCP and TLS to the edge all still work."

**SAMBHAV**, *restore*: `$ python3 backend.py A 3001` → *Backend A listening on 0.0.0.0:3001*, and requests from 10.7.16.45 appear in its log
**PRINCE**: run the loop → *B B A B A B*
**PRINCE:** "Backend A is back, and nginx is sending traffic to both backends again."

### Optional extra scenarios (spec 6.3). Record only if you have time, or show them live if the evaluator asks

### 9b. Both backends stopped
**SAMBHAV:** Ctrl+C both. **PRINCE:** `$ curl -v https://app.team1.test/api/status`
**PRINCE:** "DNS works, TCP connects, and the certificate is still verified, but we get 502 Bad Gateway from nginx with no X-Backend header. This is where the edge ends and the backend begins." **SAMBHAV:** restart both.

### 9c. Wrong destination port
**PRINCE:** `$ curl -v https://app.team1.test:9443` → *Connection refused* · `$ nc -vz app.team1.test 443` → *succeeded* · `$ nc -vz app.team1.test 9443` → *refused*
**PRINCE:** "Same host, same IP. Port 443 works and port 9443 does not. The IP address finds the machine, and the port finds the service."

### 9d. Wrong DNS server on a client
**SAMBHAV** (Mac 3): `$ sudo networksetup -setdnsservers Wi-Fi 8.8.8.8` + flush → `$ dig app.team1.test` → *NXDOMAIN* → `$ ping -c 2 10.7.16.45` → *works*
**SAMBHAV:** "The name lookup fails, but I can still ping the edge. DNS and IP are separate layers." Then `$ sudo networksetup -setdnsservers Wi-Fi 10.7.28.177` + flush.

### 9e. DNS record points to the wrong IP
**PRINCE** (Mac 1): `$ sed -i '' 's/host-record=app.team1.test,10.7.16.45/host-record=app.team1.test,10.7.7.111/' /opt/homebrew/etc/dnsmasq.conf && sudo brew services restart dnsmasq`
**SAMBHAV** (Mac 3): flush → `$ dig app.team1.test` → *10.7.7.111* → `$ /usr/bin/curl -v https://app.team1.test` → *Connection refused on port 443*
**PRINCE:** "DNS answered successfully, but with the wrong address, so the client went to a machine with no web server on 443. DNS is a directory, not a connection." Then reverse the sed (swap the two IPs), restart dnsmasq, flush and dig again → *10.7.16.45*.

---

## Scene 10 — Closing (ATANU, ~30 s)

**ATANU:** "To summarise: the name is resolved by our DNS on UDP 53. The client opens TCP to the edge on 443 and completes a TLS handshake with our own trusted CA. nginx terminates TLS and load-balances plain HTTP to two backends. Caching works with max-age and ETag 304s. We captured every layer in Wireshark. The single point of failure that remains is the nginx edge on Mac 2, and the DNS server on Mac 1. We will address both in Phase 2. Thank you."

---

### Who says what (summary)

| Member | Scenes |
|---|---|
| Prince (Mac 1) | 2, 3, 5 (client part), 6, 7, 9 (before/after/restore loops) |
| Atanu (Mac 2) | 1, 2, 4 (LAN curl), 5, 6 (log), 9 (logs, curl + ping, layer explanation), 10 |
| Sambhav (Mac 3) | 2, 3 (client dig), 4, 8, 9 (stop / lsof / restart Backend A) |

If the form's D3 video must be short, record **Scene 9 only** (about 2 min) as a separate clip. The form answer text is in `docs/D3_Failure_Demo.md`.
