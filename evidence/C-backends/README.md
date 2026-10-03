# C – Backends
- p10/p11: Backend B and Backend A terminal logs (requests from 127.0.0.1 and from nginx at 10.7.16.45).
- mac3_lsof_and_local_curl.txt: `*:3001` and `*:3002` LISTEN, plus a local `curl` to 3001 → X-Backend A.
- mac2_curl_backends_over_lan.txt: Mac 2 → 10.7.7.111:3001 (A) and :3002 (B).
