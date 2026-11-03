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
not time-limited. A successful scan sends a single `POST /helmet/pair` request, creating a
persistent, revocable device registration in PostgreSQL; only a SHA-256 hash of
its bearer credential is stored. The phone saves the returned credential to
browser localStorage **before** opening the viewer WebSocket. The socket accepts
only a saved helmet credential, never a QR invitation. Ordinary disconnects do
not require another QR scan. Pilot **Forget headset** invalidates the credential.

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
- Re-scanning an old QR on a previously registered phone uses the persistent
  local credential rather than redeeming the consumed invitation.
  A rejected QR code means it was already consumed or the panel was closed;
  it never means the registered device itself has expired.
- World notifications such as `:movement_started` are ignored by the helmet
  channel unless they are part of the intentionally limited display feed.
  Unknown world events cannot crash the viewer channel.

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

    cd apps/darkorbit_web
    mix test test/darkorbit_web/channels/helmet_channel_test.exs \
             test/darkorbit_web/controllers/helmet_controller_test.exs
    cd ../..
    npm test --prefix apps/darkorbit_web/assets

The remote repository edits were not run through an Elixir compiler or a real
Galaxy S21 during implementation. Verify migration, Phoenix joins, browser
assets, fullscreen and device performance locally.


## Troubleshooting: phone says "Socket unavailable"

Phoenix may be rejecting a saved phone credential even though the helmet page
loads over HTTP. Check the server log for
\`REFUSED CONNECTION TO DarkorbitWeb.UserSocket\` with \`helmet_token\`
and a prior database lookup of \`helmet_devices.credential_hash\`. That
means the stored credential was not authenticated; it is not proof of a bad
stereo renderer or a LAN connection failure.

The phone first verifies an existing credential via
\`POST /helmet/verify\` (Bearer authorization header, no URL token).
A stale credential is discarded **on the phone only**; the user sees an
explicit recovery instruction. If a fresh QR invitation is already open,
the phone can immediately try it instead. This does not expire valid
registrations, and ordinary network errors never erase valid credentials.

For a stale registration, open the laptop's **Atlas → PILOT HMD** panel,
choose **Forget headset**, then scan the new QR invitation. If the
headset is merely offline, leave the registration intact and reopen
\`/helmet\` on the same phone/browser instead.

Tests:
\`mix test test/darkorbit_web/controllers/helmet_controller_test.exs\`
from \`apps/darkorbit_web\`.


## Recovery after the earlier world-event crash

Old versions redeemed the invitation **inside** a viewer WebSocket join.
The first `:movement_started` event then crashed the viewer GenServer. If the
phone did not receive/save the registration credential before the crash, the
Atlas may show **PAIRED** but the phone cannot reconnect. That existing,
inaccessible registration cannot be recovered from a consumed QR code. Use
**Forget headset** on the laptop once, open the fresh QR, and scan again
after installing this update.

New versions persist the credential via `POST /helmet/pair` before the viewer
socket joins; the same failure cannot consume a QR unnoticed during joining.
