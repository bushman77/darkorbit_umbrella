# Local Galaxy HMD HTTPS (Space Nova development)

The standard `star_base` development server now launches **both** listeners
whenever you run `mix phx.server`:

- `http://127.0.0.1:4000` — desktop/Tauri gameplay
- `https://<detected-laptop-LAN-IP>:4443` — Android SBS headset, motion sensors, gaze and recenter

There is **no** `DARKORBIT_DEV_LAN_HTTPS=1` opt-in. The HTTPS listener is
mandatory in development and never changes the production/Caddy setup.

## Prerequisite: locally trusted certificate

The files must exist on your laptop:

- `apps/darkorbit_web/priv/cert/localhost.pem`
- `apps/darkorbit_web/priv/cert/localhost-key.pem`

Both files, including the private key, are ignored by Git. Never commit,
share or upload the private key or your mkcert CA key.

Use `mkcert` to create a certificate covering `localhost`, `127.0.0.1`,
and **the laptop's current LAN IP**. For example, if the address is
`192.168.0.48`:

```bash
cd ~/darkorbit_umbrella
mkdir -p apps/darkorbit_web/priv/cert
mkcert -cert-file apps/darkorbit_web/priv/cert/localhost.pem \
       -key-file apps/darkorbit_web/priv/cert/localhost-key.pem \
       localhost 127.0.0.1 192.168.0.48
openssl x509 -in apps/darkorbit_web/priv/cert/localhost.pem \
  -noout -ext subjectAltName
```

The Galaxy S21 must independently trust the mkcert CA's **public certificate**.
Install only the public CA cert on Android, never the CA private key. A
certificate served by HTTPS is not automatically trusted merely because
`curl` on the laptop succeeds. Do not bypass browser TLS warnings.

If the private LAN address changes, issue a new certificate with the new IP
and restart Phoenix.

## Normal start (no variables)

```bash
cd ~/darkorbit_umbrella
mix phx.server
```

Development automatically discovers a private IPv4 interface, preferring Wi-Fi
over wired, VPN and container interfaces. For unusual networking situations,
you can override **only the host selection**:

```bash
DARKORBIT_DEV_LAN_HOST=192.168.0.48 mix phx.server
```

The optional host override does **not** enable/disable HTTPS. When no suitable
private interface is found, or when certificate/key files are absent, startup
stops with an explicit error rather than silently offering an insecure
headset connection. The legacy single-port `DARKORBIT_DEV_HTTPS=1` mode should
remain unset when using the normal dual-port desktop/headset setup.

Verify:

```bash
ss -ltnp | grep -E ':(4000|4443)\\b'
curl -I https://192.168.0.48:4443/helmet
```

Replace the sample IP with the address your laptop discovers. Atlas's PILOT
HMD channel advertises the secure origin for QR enrollment; with a valid
matching origin and no manually edited host override, QR pairing will prefer
HTTPS automatically. Head tracking additionally requires a trusted browser
context and a direct **ENABLE HEAD TRACKING** tap on the phone.

Existing phones paired under HTTP won't automatically share local storage
with the HTTPS origin. Re-pair only after the phone trusts HTTPS. Do not
revoke an otherwise working pairing before verifying the secure endpoint.

## Scope

This changes **development** only. It does not enable the development
certificate on EC2, modify production TLS termination, or redirect the native
client away from localhost port 4000.
