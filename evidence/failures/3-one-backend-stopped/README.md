# One backend stopped — Option A (recorded 3 Oct 2026, IST) ✅

| Phase | Time (IST) | Evidence | Result |
|---|---|---|---|
| Before | 11:12:40 | Mac 1 loop; access log | `A, A, B, A, B, A`: both backends serve |
| Break | ~11:13–11:14 | Mac 3: Ctrl+C on Backend A; `lsof` shows only `*:3002` | port 3001 closed |
| After | 11:14:40–41 | Mac 1 loop; access log; error.log | `B, B, B, B, B, B`, all HTTP 200. error.log: `connect() failed (61: Connection refused) … upstream: "http://10.7.7.111:3001/api/status"`. The access log line `3001, 3002 … 200` shows nginx retrying the same request on B |
| Proof the host is up | — | Mac 2 `curl http://10.7.7.111:3001` → `Failed to connect … Couldn't connect to server`; `ping -c 2 10.7.7.111` → 2/2 replies, 0 % loss | only the process is gone |
| Restore | 11:17:51 | Mac 3 `python3 backend.py A 3001`; Backend A log shows requests from 10.7.16.45; Mac 1 loop | `B, B, A, B, A, B`: A is back in rotation |

Files:
- `option_A_terminal_outputs.pdf` and `option_A_page-*.png`: the terminal outputs from Mac 1, Mac 2 and Mac 3
- `option_A_outputs.txt`: the same text, plus the matching nginx access and error log lines exported from Mac 2

Note on the "Step 0/1" windows in the PDF: `tail -f` first prints the last 10 *old* lines, which is why they show 2 Oct entries. The 3 Oct lines in `option_A_outputs.txt` are the ones produced by this demo.
