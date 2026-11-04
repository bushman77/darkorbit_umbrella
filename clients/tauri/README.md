# SBS Space native desktop client (Tauri 2)

This is a Steam-free Linux desktop wrapper around the existing Phoenix + Three.js
game. It is **not** a second game simulation: game state, authentication,
movement, combat, inventory and encounter reconciliation remain on the
authoritative Elixir/OTP server.

The first window is a bundled offline launcher. Enter the address of a
reachable game server and choose **Launch cockpit**. It navigates the entire
webview to that server's `/play` route: Phoenix handles login, cookies,
LiveView and the authenticated `/socket` game channel. No new browser
authentication protocol, CORS proxy or special client token is required.

The launcher accepts HTTP **only** for localhost / 127.0.0.1 / ::1.
Other server origins must use HTTPS. No Tauri native IPC permissions or
OS plugins are granted to the server-hosted game page.

## Pop!_OS / Ubuntu setup

On the computer building the Linux client:

```sh
sudo apt update
sudo apt install -y libwebkit2gtk-4.1-dev build-essential curl wget file \
  libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev
```

Install Rust with the current instructions at https://rustup.rs/ and install
Node.js and npm if they are not installed.

## Configure trusted HTTPS for the local client

The Tauri launcher now defaults to **https://localhost:4001**. HTTPS is
optional for localhost generally, but it is the recommended native-client
development path. An HTTPS URL cannot connect to Phoenix's cleartext HTTP
listener on port 4000; the Bandit warning "TLS received on a clear channel"
indicates a protocol/port mismatch.

Install mkcert and its NSS trust-store helper:

```sh
sudo apt update
sudo apt install -y mkcert libnss3-tools
mkcert -install
```

Generate a **local-only** certificate in the Phoenix application's
private directory (never commit these files):

```sh
cd ~/darkorbit_umbrella
mkdir -p apps/darkorbit_web/priv/cert
mkcert -cert-file apps/darkorbit_web/priv/cert/localhost.pem \
  -key-file apps/darkorbit_web/priv/cert/localhost-key.pem \
  localhost 127.0.0.1 ::1
```

Apply migrations introduced by the new persistent-ship code, then start
Phoenix with a loopback HTTPS listener:

```sh
mix ecto.migrate
DARKORBIT_LOOPBACK_ONLY=1 DARKORBIT_DEV_HTTPS=1 mix phx.server
```

Check connectivity from another terminal:

```sh
curl -I https://localhost:4001/login
```

Phoenix now listens on HTTP **4000** and HTTPS **4001**. The HTTPS
listener is bound to 127.0.0.1 only. This is deliberately a development
configuration: for remote multiplayer, use a deployed HTTPS server,
trusted certificate, configured origins and WebSocket upgrade support.

The loopback flag is appropriate when the client and server are on the same
computer. If you only want local HTTP, run `mix phx.server` without
`DARKORBIT_DEV_HTTPS` and enter `http://127.0.0.1:4000` manually
in the launcher. Browser/webview HTTPS upgrades are not by themselves
evidence that Tauri strictly requires HTTPS for localhost.

In terminal 2, from the umbrella root:

```sh
cd clients/tauri
npm install
npm test
npm run dev
```

Choose **Use local server**, then **Launch cockpit**. The launcher opens
`https://localhost:4001/play`; an unauthenticated pilot is redirected to
`/login`. You may use development accounts provisioned by `mix setup`.

## Build and distribute without Steam

```sh
cd clients/tauri
npm run build
```

Installers are written under `src-tauri/target/release/bundle/deb/` and
`src-tauri/target/release/bundle/appimage/`. Distribute the resulting
`.deb` or `.AppImage` directly, or attach it to a GitHub Release.
On Linux, `chmod +x path/to/SBS*.AppImage` before running an AppImage.

**Important:** These are *clients*, not offline copies of the MMO backend.
A reachable Phoenix server and PostgreSQL are still required to play.
This initial version does not bundle or spawn a local server, and does not
provide automatic updates or code signing. Avoid exposing the development
server directly to the internet.

## Linux NVIDIA / WebKitGTK diagnostics

Tauri's Linux webview uses WebKitGTK, which can render WebGL differently
from Firefox/Chromium. Verify the cockpit, stereo SBS, pointer lock, mouse
wheel and Three.js performance in an actual native build.

If a NVIDIA/Wayland system shows a blank/flickering window, try:

```sh
WEBKIT_DISABLE_DMABUF_RENDERER=1 npm run dev
```

This is only a troubleshooting override, not a default; it may reduce
rendering performance. See https://v2.tauri.app/develop/debug/linux-graphics/.

Run the URL validation tests with `npm test`. The Rust/Tauri binary and
real gameplay require local build/runtime verification; neither can be
validated solely from the repository contents.

## Development watcher noise

Phoenix's file watcher may notice transient Rust build directories under
`clients/tauri/src-tauri/target` and log "Couldn't watch new directory".
This is not an SSL or Ecto failure. To keep future Rust build output outside
the umbrella while developing, launch Tauri using:

```sh
export CARGO_TARGET_DIR="$HOME/.cache/sbs-space-tauri-target"
cd ~/darkorbit_umbrella/clients/tauri
npm run dev
```
