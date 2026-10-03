# TLS certificate setup notes (own team CA)

Created on Mac 2 in `~/cn-project/certs` with OpenSSL (macOS LibreSSL).
This folder contains only **public** material: `ca.ext`, `server.ext`, `team1-ca.crt`, `app.team1.test.crt`.
The private keys (`team1-ca.key`, `app.team1.test.key`) never leave Mac 2 and are **not** in this repo.

```bash
mkdir -p ~/cn-project/certs && cd ~/cn-project/certs
# ca.ext and server.ext: see files in this folder
openssl genrsa -out team1-ca.key 2048
openssl req -new -key team1-ca.key -out team1-ca.csr -subj "/C=IN/O=Team1 CN Project/CN=Team1 Local CA"
openssl x509 -req -in team1-ca.csr -signkey team1-ca.key -days 365 -sha256 -extfile ca.ext -out team1-ca.crt
openssl genrsa -out app.team1.test.key 2048
openssl req -new -key app.team1.test.key -out app.team1.test.csr -subj "/C=IN/O=Team1 CN Project/CN=app.team1.test"
openssl x509 -req -in app.team1.test.csr -CA team1-ca.crt -CAkey team1-ca.key -CAcreateserial -days 365 -sha256 -extfile server.ext -out app.team1.test.crt
openssl verify -CAfile team1-ca.crt app.team1.test.crt        # app.team1.test.crt: OK
```

Result: subject `C=IN, O=Team1 CN Project, CN=app.team1.test`; issuer `CN=Team1 Local CA`;
valid 2 Oct 2026 07:40:15 GMT → 2 Oct 2027; SAN `DNS:app.team1.test, DNS:api.team1.test`;
EKU serverAuth; RSA 2048; 365 days (macOS requires SAN + serverAuth and rejects very long validity).

Install on nginx:
```bash
mkdir -p /opt/homebrew/etc/nginx/certs
cp ~/cn-project/certs/app.team1.test.crt ~/cn-project/certs/app.team1.test.key /opt/homebrew/etc/nginx/certs/
```

Trust the CA on **every** client Mac (only `team1-ca.crt` was AirDropped):
```bash
# Mac 2 (file is local)
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/cn-project/certs/team1-ca.crt
# Mac 1 and Mac 3 (received via AirDrop)
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Downloads/team1-ca.crt
# check
security find-certificate -c "Team1 Local CA" /Library/Keychains/System.keychain | head -5
```
No `curl -k` is used anywhere in the demo.
