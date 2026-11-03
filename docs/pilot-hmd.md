# Pilot HMD: phone SBS helmet

The laptop remains the sole authoritative pilot/controller. The phone joins a
separate **read-only Phoenix Channel** to render the same sector world locally
through the existing Three.js StereoSpaceView (no video stream).

## First-time pairing

1. Run the PostgreSQL migration and build the browser assets, including the new
   npm qrcode dependency.
2. Start the game and sign in on the laptop.
3. Open the Solar Atlas (M), then **PILOT HMD**. This is the only UI that creates
   a QR pairing invitation.
4. Ensure the displayed headset URL uses the laptop's network-reachable address,
   not localhost. Phone and laptop must reach the same server. Scan with the
   phone. There is no second approval step.
5. On the phone, tap once for fullscreen and optional landscape lock.

The QR code contains a random **single-use invitation**, not the pilot's normal
socket token, world topic, or account credentials. The invitation remains valid
while the panel stays open and is cancelled on closing it. It is deliberately
not time-limited. A successful scan creates a persistent, revocable device
registration in PostgreSQL; only a SHA-256 hash of its bearer credential is
stored. The phone retains its credential in browser localStorage and reconnects
without scanning again. Pilot **Forget headset** invalidates that credential.

## View-mode and bandwidth contract

- Atlas open -> server-set :standby. Phone canvas is black/hidden, requestAnimationFrame
  is suspended, and the helmet channel unsubscribes from tick/world telemetry.
  The small Phoenix/WebSocket connection stays alive.
- Atlas closed -> :combat. Phone subscribes to the sector topic, receives a
  fresh authoritative world snapshot, and renders local left/right SBS frames.
- Laptop 3D/SBS selection remains local. Laptop controls the ship in both cases.
- Disconnect -> device remains paired; connection state updates by process monitor.
- Helmet clients have no Core.World session and cannot call movement, combat or
  navigation commands. WorldChannel explicitly requires a pilot-role socket.

The Atlas manager reports separate pairing, connection, rendering, and mode
states. The phone reports rendering health rather than claiming it is physically
worn. Only one device is registered per pilot in the initial release.

## Running on the laptop

From the umbrella root:

    mix ecto.migrate
    npm install --prefix apps/darkorbit_web/assets
    mix assets.build
    DARKORBIT_LAN_HMD=1 iex -S mix phx.server

In development, DARKORBIT_LAN_HMD=1 intentionally enables LAN binding; without it
Phoenix stays on loopback. Prefer a trusted private hotspot, not a shared or
untrusted Wi-Fi network. Use the LAN host/IP in the
Atlas headset URL, including port. Avoid exposing these bearer tokens over an
untrusted network: deploy HTTPS/WSS for networks beyond a trusted local setup.
Phone landscape, lens alignment and frame rate require hardware testing.

## Tests

    mix test apps/darkorbit_web/test/darkorbit_web/channels/helmet_channel_test.exs
    npm test --prefix apps/darkorbit_web/assets

The remote repository edits were not run through an Elixir compiler or a real
Galaxy S21 during implementation. Verify migration, Phoenix joins, browser
assets, fullscreen and device performance locally.
