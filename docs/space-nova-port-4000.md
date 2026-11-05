# Space Nova network contract: port 4000

All game traffic uses TCP port **4000**. HTTP is permitted for local
development; public production traffic uses **HTTPS** and secure WebSockets
(`wss://`). No reverse proxy is required.

| Mode | URL |
| --- | --- |
| Pop!_OS development | `http://127.0.0.1:4000` |
| Optional trusted local TLS | `https://localhost:4000` |
| EC2 production | `https://spacenova.ddns.net:4000` |

The Tauri launcher requires an explicit `:4000` port on every server origin.
Old persisted launcher origins missing the port are migrated. Phoenix
LiveView and game sockets inherit the current browser page origin.

## Local development

```sh
cd ~/darkorbit_umbrella
DARKORBIT_LOOPBACK_ONLY=1 DARKORBIT_DEV_HTTPS=0 mix phx.server
curl -I http://127.0.0.1:4000/login
```

To use HTTPS locally, generate and trust mkcert certificates as described
in `clients/tauri/README.md`, stop HTTP, then run:

```sh
DARKORBIT_LOOPBACK_ONLY=1 DARKORBIT_DEV_HTTPS=1 mix phx.server
curl -I https://localhost:4000/login
```

One local IP/port cannot serve both HTTP and HTTPS with this setup.

## Direct HTTPS on EC2

Before restarting the production release:

1. Obtain and arrange renewal of a trusted certificate for
   `spacenova.ddns.net`. DNS-01 works without opening an HTTP port;
   ACME HTTP-01 generally requires port 80 for certificate issuance.
2. Configure the EC2 security group to allow inbound TCP **4000** from
   intended game clients. Do not expose unencrypted production HTTP.
3. Set these variables in the existing private release service environment
   (never commit the actual certificate or private key):

   ```sh
   PHX_HOST=spacenova.ddns.net
   SPACE_NOVA_TLS_CERTFILE=/absolute/path/to/fullchain.pem
   SPACE_NOVA_TLS_KEYFILE=/absolute/path/to/privkey.pem
   ```

4. Ensure the service account can read both PEM files, and restart the
   release only after the credentials and firewall are ready.
5. Test externally:

   ```sh
   curl -I https://spacenova.ddns.net:4000/login
   ```

Retire or reconfigure the previous port-443 proxy only after this endpoint
is verified. Phoenix now binds a direct public HTTPS listener on port 4000.

## SSH tunnels

SSH port forwarding does not translate HTTPS to HTTP. Forwarding directly
to production TCP 4000 carries HTTPS, and the certificate's hostname must
still match. For an ad-hoc tunnel test (with local Phoenix stopped):

```sh
ssh -N -L 127.0.0.1:4000:127.0.0.1:4000 USER@EC2_HOST
curl --resolve spacenova.ddns.net:4000:127.0.0.1 \
  -I https://spacenova.ddns.net:4000/login
```

Tauri does not have `curl --resolve`; normal desktop usage should connect
to the public HTTPS hostname. The old HTTP-based SSH tunnel address
`http://127.0.0.1:4000` will not connect to an HTTPS-only release without
a separately configured loopback HTTP listener. Do not disable certificate
verification to work around hostname mismatches.

## Rollout

This is a network configuration migration, not a running EC2 deployment.
Back up the old service and certificate configuration. Stage the
certificate, security group and launcher update before restarting the
release. Existing installed Tauri clients need a rebuild/reinstallation
(or a signed update) to adopt the new default URL. GitHub release
downloads and updater manifests still use standard GitHub HTTPS.
