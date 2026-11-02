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


## Navigation Computer V1 — authoritative waypoints

The navigation overlay is a **flat SVG chart**, not another flight camera.
Press **M** from Classic 2D, 3D Cockpit, or Stereo SBS to open it; press
**M** or **Escape** to return to the prior flight view. The original view
mode is preserved. The chart is intentionally monoscopic; users viewing
SBS through a headset must use the computer's display for chart interactions
until an in-world stereoscopic console is implemented.

- Click on the chart to add a waypoint, or type X and Y and select
  **Add coordinates**. Up to **8 waypoints** are supported.
- **Undo point** and **Clear draft** edit *local draft data only*, never the
  server's active course.
- **Engage autopilot** submits the complete route through the authenticated
  `plot_course` Phoenix Channel command. Only a successful server reply
  activates the course. The server validates all points and rejects the entire
  route if any point is outside the sector, malformed, or excessive.
- Every simulation tick advances the ship toward its current server-owned
  waypoint, then changes to the next one. The server sends
  `navigation_mode`, `destination`, and `route_waypoints` in the same
  authoritative entity snapshots used by the cockpit and minimap.
- **Stop / cancel course** sends `stop_navigation` (no coordinate payload).
  This clears destination and route under the player's session authority.
- Manual click navigation or minimap navigation calls the existing `move`
  command, which immediately replaces and cancels any autopilot route.
- On ship destruction, the server clears the active route.

**Still a 2D simulation:** these are XY sector destinations, not Z-axis
navigation, Newtonian physics, or 6DOF movement. Route planning is straight
line per leg, with no hazard avoidance or docking logic. Courses are
ephemeral map state, not persisted between sessions. The screen is not an
immersive WebXR navigation interface.

### Verification

Pure JavaScript navigation math and route safety checks were run during the
implementation. Node, Elixir, asset-build, and browser tests have **not**
yet been run in the developer's local environment. Run:

```bash
cd apps/darkorbit_web/assets && npm test
cd ../../..
mix assets.build
mix precommit
```

Then manually verify chart opening/closing from all display modes, route
engagement and multi-waypoint progression, stopping, manual overrides,
invalid coordinates, disconnects, and multiplayer visibility.

The shared tick loop still advances NPCs through their existing single-target
movement path; only player entities participate in queued waypoint transitions.


## 2026-11-01: first true XYZ world volume (foundation only)

The `sbs` branch now stores real `x`, `y` and `z` coordinates server-side,
with a bounded volume from Z=-3000 to Z=+3000 around the original 20,000 x 12,000
atlas plane. `Core.World.Movement` and Combat range use 3D Euclidean distance;
NPC pursuit uses 3D target positions; the existing deterministic simulation
ticks own all player position changes. Routes accept XYZ waypoints and the
flat SVG atlas allows selecting the target altitude.

The web client starts in single-view Three.js, with **V** switching between
3D and stereoscopic SBS. Classic 2D is no longer selectable as a playable
view. **M** opens the overhead atlas, which renders the XY projection and
shows each waypoint's Z altitude. The old 2D canvas remains as an invisible
input surface and its legacy drawing functions remain temporarily in source
for safe incremental cleanup; it does not render the main game.

For compatibility, current snapshots retain `position` and `destination`
as XY-only maps, while new `position_3d`, `destination_3d`, and
`route_waypoints_3d` fields provide full XYZ values. The sector snapshot
also carries `volume` altitude limits. This additive contract avoids silently
breaking old minimap and combat clients while allowing real volumetric travel.

The map overview is a *navigation atlas*, not a third flight camera. Cockpit
clicks select targets; plotted atlas routes are the way to move in this stage.
The legacy minimap becomes read-only.

**Deliberately deferred:** manual yaw/pitch/roll, rotational inertia,
throttle/strafe/lift controls, Cruise Flight assistance, Newtonian velocity
integration, collision/docking, and proper 3D NPC patrolling. Heading shown
during autopilot is a camera look direction, **not yet simulated ship attitude**.
Those systems should be added as an independent server-owned flight-dynamics
milestone after this volume migration is verified.

The decorative asteroid landmarks are visual reference objects only, not
server-owned targets or colliders. SBS eye spacing and headsets remain
experimental. Full `mix precommit` and browser verification are outstanding.

## Flight view cleanup — Classic 2D renderer removed

The playable flight UI now has **only** single-view 3D and stereoscopic SBS.
The V key toggles only these two modes. M opens the separate SVG navigation
atlas, which retains top-down XY mapping and altitude entry. The full legacy
Canvas 2D renderer (ship sprites, grid, stars and combat effects) has been
removed from the browser client.

For combat selection, an invisible focusable DOM input surface overlays the
visible WebGL canvas. This surface does **not** acquire a Canvas 2D context.
If WebGL initialization fails, the browser reports that failure instead
of automatically falling back to the old 2D game. HUD CanvasTexture rendering
inside the 3D cockpit remains intentionally 2D *instrument graphics*, not
a separate flight presentation.

**After pulling** the change, run `mix assets.build`, restart Phoenix,
and hard-reload Firefox (Ctrl+Shift+R) to avoid displaying a stale compiled
JavaScript or HTML template. Run Node/Elixir tests and visually check both
view modes; this commit was not browser-tested remotely.
