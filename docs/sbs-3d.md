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


## Manual flight controls — first physics slice

There are now two separate movement paths:
- **Atlas autopilot**: plot XYZ waypoints, press Engage, and the Elixir simulation
  follows the server-owned course. Opening the atlas releases held steering keys.
- **Manual cockpit flight**: keyboard submits signed throttle and rotational
  *intent* over the authenticated `flight_controls` Channel command. Core
  integrates actual orientation, velocity, and position on 100ms world ticks.
  A manual flight command cancels autopilot.

### Default keys

| Key | Function |
| --- | --- |
| `W` | Pitch nose up |
| `S` | Pitch nose down |
| `A` | Turn left (yaw) |
| `D` | Turn right (yaw) |
| `Q` | Roll left |
| `E` | Roll right |
| `=` or numpad `+` | Accelerate / raise signed throttle in 10% steps; hold to ramp |
| `-` or numpad `-` | Decelerate / lower signed throttle, through zero into reverse; hold to ramp |
| `F` | Release all held attitude controls |
| `Ctrl+E` | Toggle assisted Cruise Flight / Newtonian Flight |
| `V` | Switch single-view 3D / stereoscopic SBS |
| `M` | Open/close the navigation atlas |

### Dynamics

In **Cruise Flight** mode, the throttle represents signed desired speed
along the ship's nose. The server approaches that desired velocity with
bounded acceleration. Turning gradually curves travel toward the new
heading. At zero throttle Cruise brakes the ship; at negative throttle
it reverses direction.

In **Newtonian Flight**, throttle controls signed acceleration along the
nose, while velocity persists when throttle is zero. You can rotate,
point at a target, and continue drifting in the old direction. Negative
throttle applies reverse thrust; it does not magically zero velocity.

The server validates all control values (normalized [-1,1]); the client
cannot set position, attitude, speed or velocity. The last rotational
input expires after ten simulation ticks without refresh. Browser blur,
loss of visibility, and entering the atlas release the local held keys.
The sector boundaries absorb outward velocity. This slice uses Euler
yaw/pitch/roll angles with pitch bounded just short of vertical rather
than a quaternion-based 6DOF body-frame integrator; fine for an initial
playable cockpit, but not yet full aerospace control or rotational inertia.

**Testing status:** pure JavaScript flight controls tests passed via an
isolated runtime check. The new Core and Channel tests need to be run
with Elixir on the developer's Pop!_OS machine. Physics feel and 3D/SBS
orientation require in-browser evaluation.

## Player-selected six-key flight layout

The flight keys are now **W/S pitch**, **A/D yaw**, **Q/E roll**, with
**=/- reserved exclusively for signed throttle**. Holding =/- ramps
the throttle in deterministic 10% steps (120 ms per step), independent
of operating-system key repeat. Releasing the keys leaves the requested
throttle at its current setting; in Cruise mode the server converges
toward that speed and in Newtonian mode it continuously applies the
selected thrust. Ctrl+E switches modes while a bare E rolls right.
Holding two opposite keys on one attitude axis cancels that axis.
F releases attitude controls without resetting throttle.

The HUD exposes heading, pitch and roll independently to confirm correct
camera response. Earlier WASD-throttle mappings are obsolete.

The Three.js camera now uses the server's world-space forward direction
and a separately rolled up vector. This explicitly separates yaw from
roll and matches the server convention (+yaw right, +pitch up), with the
autopilot camera reset to world-up. Automated basis tests cover orthogonality
and each input axis. Remote browser verification remains necessary.

## Pitch-down responsiveness correction

Removed the artificial +/-89-degree pitch clamp. The authoritative pitch
now wraps continuously through straight up, straight down, and inverted
orientations, permitting genuine loops rather than stopping at vertical.
Negative pitch is downward and is never silently clamped at the horizon.

When switching directly from W to S with overlapping keydown state, the
newest pitch key wins immediately. This prevents a still-registered W
from cancelling S. Releasing the newer key resumes the older held key;
releasing both sends neutral pitch. The mono 3D flight display additionally
shows **PITCH (UP / DOWN / —)** next to the server-authoritative pitch
angle, so input handling can be differentiated from camera or server issues.

Yaw and roll remain independent. The engine still uses Euler angles and
is not yet a fully body-relative quaternion six-degree-of-freedom model.

## Angular rate limiting — smooth flight controls

Manual yaw, pitch, and roll now have **server-authoritative angular
velocity**, rather than jumping immediately to full rotation on each key
press. The controls request target rates; server ticks integrate
acceleration and use trapezoidal angular displacement to avoid a first-
tick jolt. Releasing the key brakes angular velocity smoothly to zero.
Reversing a key first brakes the old direction, then builds speed in
the new direction. The existing 10-tick input expiry brings a missing
or interrupted input to a stop.

| Axis | Maximum rate | Rate acceleration | Braking |
| --- | ---: | ---: | ---: |
| Yaw (A/D) | 44°/s | 95°/s² | 145°/s² |
| Pitch (W/S) | 38°/s | 80°/s² | 135°/s² |
| Roll (Q/E) | 56°/s | 110°/s² | 165°/s² |

These defaults are intended for playable feel and can be tuned. Each
client smooths authoritative orientation with shortest-path wrapped-angle
interpolation between 100 ms ticks; the renderer never writes back to
server positions or attitude. The rate overlay reports authoritative
pitch/yaw/roll magnitudes in degrees/sec. Cruise and Newtonian thrust
remain unchanged.

## Thrust alignment after steering

**Cruise Flight:** `Core.World.FlightDynamics` now stores a signed
`cruise_speed` instead of slowly rotating the old world-space velocity
vector toward a new destination. On every simulation tick, the server
uses the current ship attitude to calculate:

`velocity = forward(attitude) * cruise_speed`

The signed forward speed still accelerates and decelerates smoothly.
This means turning with zero throttle and then pressing `=` travels
in the new nose direction; turning while moving also steers travel
with the nose instead of leaving old-direction drift. It is deliberately
assisted flight (a full body-frame velocity constraint).

**Newtonian Flight:** Existing XYZ velocity remains independent of
heading, but new signed thrust is added in the direction the nose
currently points. A ship drifting north, then facing east and thrusting,
will move northeast until it cancels the old northward momentum.

Switching Newtonian -> Cruise retains the part of the current velocity
that points along the nose and removes sideways drift; switching
Cruise -> Newtonian preserves the current world-space velocity. Atlas
autopilot remains a separate route-following mode.

The server includes unit tests for turning after acceleration, turning
during acceleration, pitching into vertical travel, reverse throttle
and the mode transition. Client world-to-scene basis tests ensure the
cockpit points along the same direction the server accelerates.

## Space Rogue-style manual lasers

Space now fires the ready X1 laser along the **server-authoritative
live heading**, rather than resolving the selected target automatically.
The server tests the forward 3D ray against living NPC collision spheres
(40 world-unit radius, comparable to the current rendered NPC size);
the closest intersection within the laser's range is hit. An unselected
NPC directly ahead can be hit, while a locked target outside the sight
line is missed. Every valid shot consumes the emitter's existing cooldown
and broadcasts `laser_fired` with authoritative XYZ endpoints and
`hit: true/false`. The 3D/SBS renderer draws a bright red laser with a
soft red glow even on a miss.

Holding Space can request another shot when the *server-reported*
cooldown completes; key repeats cannot spam the channel. Losing focus,
opening the navigation atlas or releasing Space stops held manual fire.
Core continues to own damage and multiplayer synchronization.

T is currently a nearest-hostile acquisition shortcut; L toggles the
existing automatic laser lock (same as Ctrl or slot 1). Classic
Space Rogue had T targeting, R ready-weapon switching and L manual/
automatic laser mode. R is deferred until additional weapons exist.
Automatic lock-on currently uses the existing selected-target system,
while manual fire uses the new actual forward ray.

## Unobstructed cockpit and Space focus handling (2026-11-01)

The right-hand Combat Relay / Target Information panel was removed from
the cockpit and saved-layout schema. A minimal pointer-transparent combat
message remains at the lower left; target name and aiming remain in the
3D/SBS instrument HUD. T targets the nearest hostile, L/Ctrl/1 toggles
automatic fire, and Space is nose-aimed manual firing.

Space is captured before the browser can turn a focused HUD button into
a native click, even when the key repeats. Editable text fields and the
open navigation atlas retain normal keyboard behavior. Existing player
layouts with target_info entries are sanitized to omit this window.

## Body-relative six-degree-of-freedom attitude (2026-11-01)

Previously the game accumulated independent yaw/pitch/roll Euler angles
anchored to the world axes. This caused pitch after rolling to ignore
the ship's local 'up': turning W/S could feel bound to the orientation
from login. The authoritative Elixir simulation now stores a normalized
quaternion `orientation` alongside the legacy `attitude` counters.
Each server tick integrates the existing capped angular rate then
right-multiplies the new body-local yaw/pitch/roll quaternion.

The server projects cruise thrust and manual red-laser aim through the
same quaternion's local nose, so camera, thrust and hit testing all
refer to the current ship heading. The 3D/SBS renderer uses the received
quaternion directly and performs shortest-arc, frame-rate independent
slerp to avoid visual snapping. Heading/pitch/bank readouts now derive
from the orientation rather than the old summed control counters.

Roll 90°, then hold W: the nose should move horizontally relative to
the world because the ship's own 'up' axis is now sideways. No pitch
limit or fixed world-axis pitch is imposed. Autopilot's destination
camera remains separate.

## Wing-mounted dual red lasers

The single visual laser offset has been replaced with a **server-owned
pair of muzzle hardpoints**. In scene ship coordinates, the left/right
hardpoints are (±1.75, +1.3, -3.2) scene units from the ship centre,
with the pilot eye at (0,+2.75,0); the game-to-scene scale remains 0.06.
The server rotates both offsets with `Core.World.Orientation`, casts
two independent rays down the actual ship nose, tests the nearest
living NPC collision sphere and uses the existing max range/cooldown.
The crosshair ray and symmetric muzzles both intersect a centred
40-world-unit NPC sphere within range; the ray is never steered toward
an arbitrarily selected target. NPC mesh centres are now rendered
at their actual authoritative positions rather than offset vertically.

Each valid burst consumes one cooldown. If both rays hit one NPC, it
receives the normal weapon damage once; if two different NPCs intersect
separate rays, damage is divided between them. Both beam endpoints,
`hit` flags, and impacted target states are sent in the authoritative
`laser_fired` event. The client renders thin red cores, red glows and
short bright impact flashes only for actual hits. Automatic targeted
fire retains its existing lock-on rules and receives a matching pair
of visual wing beams. Clients must never calculate damage or authoritative
hits from selected IDs.

## Extended-range combat and unmistakable confirmation (2026-11-01)

The player pulse emitter now reaches **3,600 world units** (previously
720), equivalent to 216 Three.js scene units using the existing 0.06
world-to-scene scale. This is a server-side balance change in
`Core.Combat.player_weapon/2`; `World.MapServer` uses the same
range for the twin-wing manual ray collision and for existing automatic
target attack validation. Existing NPC weapon ranges are unchanged.
Shots past this range still miss and consume cooldown; an enemy being
selected does not override the manual line of fire.

The cockpit reports `HIT 2/2  SH -24  HULL -16` (using the actual
server damage values) or `MISS / NO IMPACT` for 1.6 seconds after
the authoritative `laser_fired` event. 3D gets a small reticle-adjacent
confirmation and hit/miss reticle color; SBS puts the confirmation into
each eye's cockpit HUD rather than a flat overlay. The HUD continuously
shows selected-target Euclidean XYZ distance, maximum player laser
range, range status, and remaining NPC shields/hull. The red beams
are thicker, remain visible for 550 ms and have larger impact flashes.

No client-side damage inference, aim assist, automatic target snapping,
or new weapon recharge behavior was added.

## Sector 1-1 Dart starter fighter (2026-11-02)

The previous Rift Skirmisher placeholders (three orange octahedrons)
have been replaced by **one Dart-class pirate fighter**. The default
`Core.NPC.Catalog` now spawns only `npc:1-1:dart:1` at world XY
`(1480,1000)`. It uses the existing authoritative NPC FSM and 30
simulation-tick respawn delay (3 seconds at the default 100ms tick).
No parallel second NPC is spawned while the Dart is alive. After
destruction it is removed, then that same unique identity respawns.
Sector NPC stats are temporarily balanced for the demo; `max_hull =
245` follows the 1989 Dart's published armor, while shields/damage/
speed/cooldowns are estimates pending directional shields, ECM,
Garnet lasers and SM-1 gameplay.

The browser chooses `createDartModel(THREE)` for `npcTypeId === "dart"`,
in both conventional 3D and stereo SBS, preserving renderer ownership.
The original-generated lightweight polygonal ship has a swept
delta-shaped orange hull, dark canopy, central dorsal fin, and twin
engine housings. Its nose orientation follows the NPC's movement/
combat targeting; server-authoritative XYZ collision and damage
spheres are unchanged. Existing legacy/future NPC types retain the
generic fallback mesh.

Reference manual illustration and specifications:
https://cdn.steamstatic.com/steam/apps/569200/manuals/space_rogue_manual.pdf#page=36
