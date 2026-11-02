# SBS 3D display prototype (branch: sbs)

This experimental renderer introduces a Three.js cockpit, real 3D geometry and
independent left/right stereo perspectives. It **does not** yet implement 3D
flight physics or WebXR. Existing Core.World authority and XY positions remain
unchanged; XY positions render on a 3D ground plane.

## Try it
- From the umbrella root run `mix setup` to install the pinned Three.js npm package.
- Run `mix phx.server`, sign in and launch the existing game.
- Choose **3D cockpit** or **Stereo SBS** from the VIEW selector.
- Press **V** to cycle Classic 2D → 3D → Stereo SBS → Classic 2D.
  This keyboard shortcut restores the classic view when SBS hides HTML panels.
- Pointer targeting uses 3D raycasting for NPCs. Ground-plane clicks submit
  server-validated destinations, while sky clicks do not issue a destination.
- Combat commands, existing hotbar keyboard shortcuts and Phoenix Channels
  remain server-authoritative.

## Boundaries
- `stereo_math.mjs` projects Core.World XY onto the XZ visual plane and maps
  pointer coordinates for independent eye viewports.
- `stereo_view.js` owns the 3D scene, procedural geometry, stereo cameras and
  cockpit-mounted CanvasTexture instrumentation. It never sends game commands.
- `client.js` owns the socket, interpolation, input commands and renderer
  selection. The original 2D renderer remains the default.
- Existing SVG/Canvas cockpit panels remain in classic/desktop modes; in SBS
  they are hidden because a single DOM overlay cannot produce proper binocular
  depth. The 3D cockpit texture is rendered once per eye.

## Limitations and verification
- The server is still 2D. 3D ship altitude, six-degree-of-freedom
  acceleration, yaw/pitch/roll mechanics and Newtonian flight are future work.
- SBS is not an immersive WebXR session, and does not correct headset lenses
  or track head movement. Eye spacing is provisional.
- Ground-plane mouse steering is a prototype and requires real browser testing.
- No manual browser or headset test has been performed.
- Run `cd apps/darkorbit_web/assets && npm test`, then
  `mix assets.build` and `mix precommit` from the umbrella root.
- Perform manual checks of switching, targeting, movement, multiplayer state
  and binocular comfort on supported headsets.

## Cockpit framing revision (SBS acceptance screenshot)

- Repositioned the instrument surface to fit within the eye frustum and keep
  telemetry legible rather than being cropped below the viewport.
- Peripheral canopy braces are thinner and moved toward the sides.
- Dashboard size adapts to the per-eye perspective aspect ratio; this is
  checked by `stereo_layout_test.mjs`.
- Removed the monoscopic desktop instruction hint during SBS mode.
- The first SBS screenshot was provided from Firefox on Pop!_OS and establishes
  that the mode renders. It does **not** yet establish headset comfort, accurate
  stereopsis, or complete gameplay control verification.
