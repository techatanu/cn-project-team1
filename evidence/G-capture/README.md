# G – Capture
- `phase1_full_flow.pcapng`: 683 packets, captured on Mac 3 en0. It contains the DNS lookups, the TCP and TLS 1.2/1.3 handshakes, the encrypted application data, and all six nginx→backend plain-HTTP connections.
- `phase1_full_flow_tshark_summary.txt`: the key frames, extracted with tshark (DNS TTL 60, ARP, handshake, ciphers, X-Backend A/B/A/B/A/B, conversations).
- Screenshots: p15, p17–p22, and pkt240_dns_response_ttl60.png (Answers expanded: TTL 60, 10.7.16.45).

The separate "bonus" file we received was a byte-identical copy of phase1_full_flow.pcapng, so it is not included. Nothing is lost: the plain-HTTP edge→backend streams are in the main capture (filter `tcp.port == 3001 or tcp.port == 3002`, then Follow → TCP Stream).
