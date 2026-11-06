# Space Nova production networking — Caddy HTTPS and Phoenix

Space Nova's existing AWS EC2 deployment uses Caddy to terminate TLS on
public **443**, proxying to Phoenix HTTP on **127.0.0.1:4000**.

```
Internet HTTPS/WSS :443 --> Caddy --> 127.0.0.1:4000 Phoenix HTTP/WS
                                        |
                                     PostgreSQL
```

Verified on 2026-11-06: `https://spacenova.ddns.net/login` returned
HTTP/2 200 with server `Caddy`, and Phoenix listened on localhost:4000.
No separate Let's Encrypt client or certificate files are needed by Phoenix:
Caddy owns TLS issuance and renewal.

| Mode | Client URL | Phoenix listener |
| --- | --- | --- |
| Current EC2 (Caddy) | `https://spacenova.ddns.net` | `http://127.0.0.1:4000` |
| Local development | `http://127.0.0.1:4000` | localhost HTTP port 4000 |
| Optional direct TLS | `https://HOST:4000` | HTTPS port 4000 |

## Current EC2 deployment (recommended)

Existing `/etc/caddy/Caddyfile`:

```caddy
spacenova.ddns.net {
    reverse_proxy 127.0.0.1:4000
}
```

Set this mode explicitly in the private environment file read by
`space-mmo.service` at `/home/ubuntu/.config/space_mmo.env`:

```sh
SPACE_NOVA_PROXY_MODE=true
PHX_HOST=spacenova.ddns.net
```

The release also needs existing `DATABASE_URL` and `SECRET_KEY_BASE`.
In Caddy proxy mode, `SPACE_NOVA_TLS_CERTFILE` and
`SPACE_NOVA_TLS_KEYFILE` are not required.

This is deliberately opt-in: absent `SPACE_NOVA_PROXY_MODE=true`, the
production release still requires direct TLS cert/key files and runs HTTPS
on port 4000. Do not enable proxy mode unless a trusted proxy actually
terminates public TLS and the backend remains private on loopback.

Caddy sends a trusted `X-Forwarded-Proto` value and discards spoofed
client-supplied values. Phoenix uses that header for SSL scheme and HSTS
policy. The backend binds only `127.0.0.1`, not `0.0.0.0`.
Do not open TCP port 4000 in the EC2 security group for proxy mode.

Confirm after deployment:

```sh
sudo systemctl status space-mmo --no-pager
sudo ss -lntp | grep -E ':(443|4000)\b'
curl -sSI http://127.0.0.1:4000/login | head -1
curl -fsSI https://spacenova.ddns.net/login | head -1
curl -fsSI https://spacenova.ddns.net/play | head -1
```

To check websocket connections, use the actual desktop or browser client.
Caddy's reverse proxy supports the WebSocket upgrade automatically.

## Local development

```sh
cd ~/darkorbit_umbrella
DARKORBIT_LOOPBACK_ONLY=1 DARKORBIT_DEV_HTTPS=0 mix phx.server
curl -I http://127.0.0.1:4000/login
```

Optional local TLS remains available via
`DARKORBIT_DEV_HTTPS=1` with developer-only certificates.

## Optional direct TLS deployment

For installations without a proxy, do not set `SPACE_NOVA_PROXY_MODE`.
Supply these private environment variables:

```sh
PHX_HOST=your.hostname
SPACE_NOVA_TLS_CERTFILE=/real/path/to/fullchain.pem
SPACE_NOVA_TLS_KEYFILE=/real/path/to/privkey.pem
```

Obtain trusted certificates and configure renewal separately. Port 4000
must be permitted by your firewall/security group, and the server binds
HTTPS directly. This mode is not used by the current EC2 host.

## Tauri launcher and backwards compatibility

The new Tauri launcher defaults to `https://spacenova.ddns.net`
(standard HTTPS 443). It migrates a saved
`https://spacenova.ddns.net:4000` origin automatically. Public servers
must use HTTPS 443 or explicitly configured direct TLS 4000. Local HTTP
development must use loopback and port 4000.

Older already-installed launchers may still point to port 4000 and
must be updated or manually reconfigured until a new signed client
release is installed. These desktop changes do not alter the
server-hosted Android SBS viewer or game websocket routes.

## Controlled deployment

The `space-nova-server-linux-x64.tar.gz` archive built before adding
proxy mode **cannot run** against the current EC2 environment file.
Rebuild from the updated `sbs` checkout and upload the new archive.
Stage it separately, retain the PostgreSQL and application backups,
configure proxy mode, run any migrations through the release entrypoint,
and switch `space-mmo.service` through systemd. Keep the existing Caddy
configuration and certificates in place.

See `docs/space-nova-release.md` for the release distribution procedure.
