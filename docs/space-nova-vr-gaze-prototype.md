# Space Nova: Galaxy S21 SBS head-gaze prototype

This experimental headset mode keeps Phoenix world/flight authority on the
laptop and sends **no orientation data or gaze commands over a socket**.
Headset motion rotates only its own local Three.js camera; a cockpit-mounted
NAV control activates after 1,000 ms of sustained gaze followed by 800 ms
of visible radial confirmation. Look away to cancel. NAV, CLOSE and RECENTER
are local, read-only controls. Keyboard/mouse flight stays unchanged.

## Why HTTPS matters

Android browsers can require a secure context for `DeviceOrientationEvent`.
On plain `http://<LAN-IP>:4000/helmet`, Space Nova displays
"Head tracking needs HTTPS" and continues normal SBS without gaze controls.

An optional development-only TLS listener lets the phone use
`https://<LAN-IP>:4443/helmet` **while retaining local HTTP :4000 for Tauri**.
TLS is opt-in, with exact expected phone Origin matching for Phoenix sockets.

### Create a locally trusted test certificate

Install `mkcert` on the Pop!_OS laptop. Identify the actual Wi-Fi/LAN IPv4
used by the Galaxy S21 (for example with `hostname -I`; do not accidentally
use a Docker, VPN or loopback address). Substitute it below:

```sh
cd ~/darkorbit_umbrella
LAN_IP=192.168.1.123   # replace with laptop's LAN address

mkdir -p apps/darkorbit_web/priv/cert
mkcert -install
mkcert -cert-file apps/darkorbit_web/priv/cert/localhost.pem \
  -key-file apps/darkorbit_web/priv/cert/localhost-key.pem \
  localhost 127.0.0.1 "$LAN_IP"

DARKORBIT_LOOPBACK_ONLY=1 \
DARKORBIT_DEV_HTTPS=0 \
DARKORBIT_DEV_LAN_HTTPS=1 \
DARKORBIT_DEV_LAN_HOST="$LAN_IP" \
mix phx.server
```

The private key remains on the laptop and is ignored by Git. Never commit
`localhost-key.pem`, the mkcert root CA private key, or authentication tokens.

The phone must also **trust the local mkcert CA**. Transfer only the public
`rootCA.pem` from the directory reported by `mkcert -CAROOT` to the Galaxy
S21; install it as a user CA certificate in Android's security/certificate
settings. Depending on the browser and Android policy, user-installed CA
trust may need verification. Do not transfer `rootCA-key.pem`. Remove the
test CA from the phone after testing if it is no longer needed.

The laptop and phone must be on the same trusted network and TCP :4443
must be reachable. Do not expose this development listener on the Internet.

### Connect the existing headset

1. Start Tauri as usual with `cd clients/tauri && npm run dev`. It still
   connects over the normal localhost HTTP path.
2. In the Atlas **PILOT HMD** pairing panel, set the helmet host to
   `https://<LAN-IP>:4443` before generating/scanning the QR code.
3. Open the resulting `/helmet` address in the Galaxy S21 browser. Confirm
   it is HTTPS with no certificate warning.
4. Tap **ENABLE HEAD TRACKING**. The status should eventually read
   "Head tracking active". If it shows HTTPS required, denied, unsupported,
   or remains waiting, do not expect head-gaze to work.
5. Tap **ENTER FULLSCREEN VR** and fit the phone in the SBS holder.
6. Enter cockpit mode from the laptop. Turn your head right and slightly down
   to the green NAV switch, hold for one second, then wait for the progress
   ring to fill during the next 0.8 seconds.
7. In the opened navigation panel look at **CLOSE** or **RECENTER**.
   Holding a target does not repeatedly trigger. Moving your head away
   cancels an unfinished activation.

## First-flight acceptance checks

- Head yaw, pitch and roll should rotate the scene but **not** turn the ship.
- The blue cockpit framing, dashboard and NAV switch stay in ship space.
- Both eyes see the same reticle/countdown without sideways image drift.
- NAV opens and CLOSE dismisses a local read-only information panel.
- RECENTER sets the current head direction as neutral.
- Switching away from combat, losing tracking or hiding the tab cancels
  incomplete dwell interactions. Normal mouse flight and weapons continue
  unchanged on the laptop.

This is intentionally not a full VR navigation computer and does not
transfer route planning, docking, firing or purchases to head-gaze. Those
will need separately authorized, confirmed commands in later iterations.
