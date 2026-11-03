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
4. The Atlas automatically suggests a laptop LAN address for the QR link,
   even when you opened the game at localhost. It prefers Wi-Fi, then wired
   LAN, and shows other available IPs in the pairing address field. Choose
   another entry or type a reachable address if the suggestion is wrong.
   Phone and laptop must reach the same server. Scan with the phone;
   no second approval step is needed.
5. On the phone, rotate to landscape and tap **ENTER FULLSCREEN VR**.
   Android's browser requires this tap; QR navigation cannot request fullscreen
   automatically. If the browser blocks fullscreen, the page offers a windowed
   fallback. The stereo display stays black in Atlas/standby.
6. If the two headset images do not fuse comfortably, open **Lens alignment
   settings** before entering VR. Adjust the center gap and eye separation.
   Values are remembered on the phone and SBS uses separate, nonoverlapping
   eye viewports. Exiting fullscreen returns to the setup controls.

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
- Phone disconnect -> device remains paired; connection state updates by process monitor.
- Laptop/controller disconnect -> headset mode becomes standby immediately; the
  phone cannot continue receiving world updates after the controlling session closes.
- Helmet clients have no Core.World session and cannot call movement, combat or
  navigation commands. WorldChannel explicitly requires a pilot-role socket.
- Re-scanning an old QR on a previously registered phone must use the persistent
  local helmet credential rather than attempting the consumed invitation.
  A refused new pairing code means it was used, cancelled or the Atlas panel
  was closed. Reopen the panel and scan a fresh code if not already paired.

The Atlas manager reports separate pairing, connection, rendering, and mode
states. The phone reports rendering health rather than claiming it is physically
worn. Only one device is registered per pilot in the initial release.

## Running on the laptop

From the umbrella root:

    mix ecto.migrate
    npm install --prefix apps/darkorbit_web/assets
    mix assets.build
    DARKORBIT_LAN_HMD=1 iex -S mix phx.server

In development, DARKORBIT_LAN_HMD=1 intentionally enables LAN binding; without
it Phoenix stays on loopback. Prefer a trusted private hotspot, not a shared
or untrusted Wi-Fi network. You can override auto-discovery by setting
DARKORBIT_HMD_HOST to the preferred laptop hostname or IPv4 address.
The QR link uses the current page's scheme and port with that host. If there
are no usable LAN interfaces, manually enter the reachable URL in the Atlas. Avoid exposing these bearer tokens over an
untrusted network: deploy HTTPS/WSS for networks beyond a trusted local setup.
Phone landscape, lens alignment and frame rate require hardware testing.

## Tests

    mix test apps/darkorbit_web/test/darkorbit_web/channels/helmet_channel_test.exs
    npm test --prefix apps/darkorbit_web/assets

The remote repository edits were not run through an Elixir compiler or a real
Galaxy S21 during implementation. Verify migration, Phoenix joins, browser
assets, fullscreen and device performance locally.
