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

Start the **existing** server from the umbrella root in terminal 1:

```sh
mix setup                 # first time only; requires PostgreSQL
DARKORBIT_LOOPBACK_ONLY=1 mix phx.server
```

The loopback flag is appropriate when the client and server are on the same
computer. For remote multiplayer, deploy the server separately with HTTPS,
WebSocket upgrade support and appropriate origin/secret configuration.

In terminal 2, from the umbrella root:

```sh
cd clients/tauri
npm install
npm test
npm run dev
```

Choose **Use local server**, then **Launch cockpit**. The launcher opens
`http://127.0.0.1:4000/play`; an unauthenticated pilot is redirected to
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
