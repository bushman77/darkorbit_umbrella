# Darkorbit Umbrella

An experimental Elixir/OTP and Phoenix space-MMO server. The server is being
built as an authoritative game system: clients submit intentions, while
identity, ownership, inventory, equipment, progression, economy, and world
state are validated and owned by the server.

The completed vertical slice includes persistent player-state domains, a
deterministic ship-stat engine, a supervised authoritative starting map,
server-owned NPC combat, and an authenticated multiplayer Canvas 2D browser
client for sector 1-1.

## Requirements

- Elixir 1.15 or newer with a compatible Erlang/OTP release
- PostgreSQL 14 or newer
- A local `postgres` role with password `postgres` for the checked-in
  development and test configuration, or equivalent local config overrides

Production reads `DATABASE_URL`, `SECRET_KEY_BASE`, `POOL_SIZE`, `PORT`, and
optionally `ECTO_IPV6` from the environment. Never commit production secrets.

## Development

From the umbrella root:

```console
mix setup
mix phx.server
```

The setup alias fetches dependencies, creates and migrates `darkorbit_dev`,
seeds two playable pilots, and installs/builds the browser assets. Open
<http://localhost:4000> after the server starts, choose **Launch browser
client**, and sign in with either development account:

```text
demo_pilot / launch-sector-11
wing_pilot / launch-sector-11
```

Open a normal and private browser window with one account in each to see both
ships and the same NPC encounter. Left-click or hold empty space in the
viewport to fly, select an NPC without firing, then press Ctrl, press 1, or use
**Toggle laser** to start and stop X1 automatic fire. Escape clears the target.
Manual fire is now **right mouse button held down** over the cockpit
viewport. Space no longer fires (it is unassigned). The server validates each intention and broadcasts
tick-owned positions, engagement, health, damage, destruction, and respawning
back to all clients.

Useful commands:

```console
mix test
mix precommit
mix hex.audit
```

`mix precommit` compiles with warnings treated as errors, removes unused lock
entries, formats the project, and runs the complete umbrella test suite. The
test aliases create and migrate `darkorbit_test` automatically. Run
`mix hex.audit` before releases to check the locked Hex packages against current
retirements and security advisories.

The game transport uses `world:1-1` on `/socket`. Browser sessions issue a
short-lived signed socket token. Channel commands contain only movement,
target-selection, target-clearing, and laser-fire intentions. Core owns
sessions, map bounds, positions, health, damage, cooldowns, NPC decisions, and
simulation ticks. Original placeholder graphics live under
`apps/darkorbit_web/priv/static/images/game`; their categories and dimensions
are defined in `assets/js/game/asset_catalog.js`.

## Architecture

See [docs/architecture.md](docs/architecture.md) for application boundaries,
transaction invariants, the audited baseline, and the next implementation
milestone. The longer-term direction is tracked in [ROADMAP.md](ROADMAP.md).


## Experimental stereo cockpit on `sbs`
The `sbs` branch adds optional Three.js 3D cockpit and side-by-side stereo
rendering without changing the authoritative 2D world simulation. Press **V**
to cycle Classic 2D → 3D Cockpit → Stereo SBS. See
[docs/sbs-3d.md](docs/sbs-3d.md) for setup and caveats.


### Navigation Computer V1 (experimental SBS branch)
Press **M** to open the full-sector SVG overview from any flight view.
Click up to eight waypoints, select **Engage autopilot**, then return to
the cockpit with **M** or **Esc**. A server-owned route advances across
simulation ticks; **Stop / cancel course** halts it, and manual steering
overrides the route. See [SBS navigation notes](docs/sbs-3d.md).


### True XYZ space foundation (experimental `sbs` branch)
The cockpit now opens directly in **3D**. **V** toggles 3D and stereo SBS,
and **M** opens the top-down **sector atlas**. Plot XYZ waypoints by clicking
the atlas and choosing the Z altitude, or enter all three coordinates.
Routes are simulated and validated on the Elixir server. The old 2D gameplay
view has been retired from the selector; the atlas is the overhead map.
Flight physics (yaw, pitch, roll, Cruise Flight, Newtonian) are the next step.
See [the SBS architecture notes](docs/sbs-3d.md).

### Flight display cleanup

Classic 2D is no longer an available flight view on `sbs`. The game
requires WebGL and presents only **3D** or **Stereo SBS** (`V` toggles).
The atlas (`M`) remains a separate top-down SVG navigation computer.
After updating this branch, rebuild web assets and hard-refresh the browser.


### Fly the ship manually (experimental SBS branch)

The flight layout is **W/S pitch up/down**, **A/D turn left/right**,
**Q/E roll left/right**, and the **mouse wheel for target throttle**.
Wheel up increases signed throttle by 5% per notch; wheel down decreases it,
passing through neutral into reverse. The setting remains at the chosen
level when you stop scrolling. **Hold Ctrl while scrolling over the cockpit
flight viewport to roll the ship**: Ctrl+wheel up banks right (E direction);
Ctrl+wheel down banks left (Q direction). Each notch commands a short roll
pulse and then releases automatically; scrolling repeatedly extends the bank.
Ordinary scrolling still adjusts throttle. `Q/E` remain roll alternatives,
and `=/-` remain keyboard throttle alternatives. Mouse controls are accepted
only over the active cockpit flight viewport; scrolling in the Atlas or other
controls retains its normal meaning. Ctrl+wheel is prevented from zooming
the browser when the cockpit receives it; OS/browser-reserved gestures may
take priority on some systems.

**Ctrl+E** switches between **assisted Cruise Flight**, where the server
smoothly accelerates toward your requested speed and brakes when you dial
throttle down, and **Newtonian Flight**, where neutral thrust preserves
existing momentum. **F** releases held attitude controls. The flight HUD
shows heading, pitch, roll, commanded throttle and actual velocity.
**M** opens the navigation Atlas for optional XYZ autopilot routes.

**Optional mouse-look steering:** In **Solar Atlas → Cockpit control preferences**,
enable **mouse-look steering** and optionally adjust sensitivity (0.4×–6.0×).
The setting is remembered per pilot in the current browser. Return to the
cockpit, then **left-click the flight background once** to capture the pointer.
Moving the mouse right/left turns the ship (yaw), moving up/down pitches
the ship, and stopping mouse movement releases the steering input after a
brief interval. Mouse input now uses approximately **2× the original gain at
1.0× sensitivity**, plus a faster server-bounded turn profile when the mouse
is actually captured: up to **100°/s yaw** and **88°/s pitch**. The original
keyboard-only caps (44°/s yaw, 38°/s pitch) remain unchanged outside mouse
capture. The server still owns the resulting angular acceleration,
orientation and movement. **Esc** releases the pointer without changing the
flight mode; **M** opens the Atlas and releases it automatically. A quick
left-click after capture selects the centered target; **T** selects the nearest
hostile, and right mouse still fires lasers. While pointer-locked, accidental
**V** presses cannot change the display; release with Esc to use V normally.
W/S, A/D, Q/E, wheel throttle and Ctrl+wheel roll continue to work, with
keyboard pitch/yaw taking priority on any held axis. The feature defaults off
so the original cockpit behavior is unchanged until deliberately enabled.
Browser support for Pointer Lock is required for the optional mode.

Mouse steering still buffers nearby mousemove events while the pointer
is moving, but now **sends zero yaw/pitch without any easing or trailing
coast** after approximately 55ms with no movement. The zero input bypasses
ordinary client command throttling. On the next server simulation tick, mouse
yaw/pitch angular velocity snaps to zero; keyboard steering keeps its smooth
braking model, and translational flight inertia is unchanged. Actual response
is subject to browser frame scheduling and the server tick. If Firefox releases
pointer lock (for example after Esc, switching windows or opening Atlas),
the cockpit explicitly displays **MOUSE STEERING PAUSED · CLICK COCKPIT TO
RESUME**. Click inside the cockpit once to recapture; this is a browser
security restriction and cannot be bypassed by automatically locking again.
The saved Atlas mouse setting and sensitivity are unchanged.

See [SBS flight and navigation notes](docs/sbs-3d.md).

### Rebuild the 3D cockpit JavaScript after changes

The umbrella root forwards `mix assets.setup`, `mix assets.build`, and
`mix assets.deploy` to `apps/darkorbit_web`, where the Phoenix
esbuild/Tailwind aliases are defined. After updating `sbs`, stop the
server and from the repository root run:

```sh
mix assets.build
grep -n -m1 'lastPitchKey' apps/darkorbit_web/priv/static/assets/js/app.js
```

If that grep does not match, the compiled JS is still outdated or the
build failed. Do not diagnose pitch controls in Firefox until the bundle
contains the current mapping. Restart Phoenix and hard-refresh the tab.
The current flight input source uses W/S for pitch, A/D for yaw, Q/E for
roll, mouse wheel for signed throttle, and =/- as keyboard fallbacks;
X is intentionally unassigned.

### Smooth turning and rolling (SBS)

Holding W/S, A/D, or Q/E ramps the ship's angular velocity gradually
toward a capped pitch/yaw/roll rate. Releasing a key smoothly brakes the
turn; pressing the opposite key brakes then reverses rotation. Actual
angular motion is integrated by the Elixir world server. The cockpit
renders interpolated attitude between updates for fluid 3D/SBS motion.
See the tuning table in [SBS flight notes](docs/sbs-3d.md).

### Heading-aligned Cruise Flight

In Cruise mode, the ship moves in the direction its **nose currently
faces**. Turning then accelerating does not reuse the original spawn
heading, and turning while moving redirects cruise travel. In
Newtonian mode, the ship retains momentum while newly applied thrust
follows its live heading. See [thrust alignment notes](docs/sbs-3d.md).

### Space Rogue-style manual red lasers (SBS)

In the 3D or stereo cockpit, **holding right mouse button (RMB)** fires
the currently ready X1 laser along the *ship's present nose direction*.
Holding RMB fires
additional shots only when the server-owned cooldown allows them.
Shots that miss still draw a visible bright red laser beam and consume
the same cooldown. An enemy must actually intersect the forward laser
ray within weapon range to take damage; merely having a target selected
does not cause manual shots to hit.

**T** acquires the nearest hostile for the targeting computer.
**L** switches the existing X1 automatic laser engagement on/off;
the legacy Ctrl and hotbar slot 1 remain available for the same toggle.
Manual shots do not replace or alter the automatic laser toggle and
do not require a selected target. **R** weapon cycling can be added
when a second ready weapon exists. The server exclusively owns shot
origin, heading, damage, range and cooldown.

### Fully ship-relative flight axes

The SBS branch now integrates local ship yaw, pitch and roll into an
authoritative quaternion. Pitch is no longer tied to the original world
orientation: roll the ship and W/S follows its rotated local up/down.
The same forward orientation drives cruise thrust and nose-aimed red lasers.
The 3D/SBS client slerps the quaternion between server snapshots.

### Twin wing-mounted red lasers

Manual RMB fire now launches two simultaneous, genuine 3D rays from
physically symmetric wing emitters. The muzzles belong to the ship's
server-owned quaternion orientation, so yaw, pitch and roll move the
mounts with the craft. Each ray can hit or miss independently; NPCs
within range receive server-authoritative shield/hull damage, and
collisions are replicated to all clients as paired impact endpoints.
A single RMB activation uses one cooldown and the original total
damage budget: double hits on the same NPC do not double the damage.
Existing lock-on automatic laser fire also renders both wing beams.
Bright red impact flashes indicate confirmed hits; no-target shots
show two red streaks with no hit flash.

### Extended player laser reach and clear hit feedback (SBS)

The pulse emitter's **server-enforced range is 3,600 world units**,
increased from 720 (5×). The same range governs the two manual wing
rays, automatic X1 engagement, and beam endpoints on misses.
The 3D/SBS cockpit shows a selected target's actual 3D range,
`IN RANGE`/`OUT OF RANGE`, and shield/hull values.
Every server-confirmed shot shows a visible **HIT N/2** or **MISS**
status for 1.6 seconds, with negative shield/hull damage on hits.
The reticle briefly changes green on hit and red on miss. The red
beams persist for 0.55 seconds with enhanced collision flashes.
A selected target is *not* automatically hit by manual RMB fire:
the player's nose and the two authoritative rays still determine hits.

### Sector 1-1 starter Dart (2026-11-02)

The demo now starts with **one** NPC instead of three: an orange **Dart**
pirate fighter, modelled as original low-poly delta-wing geometry in
`apps/darkorbit_web/assets/js/game/dart_model.mjs`. Its pointed nose,
wide swept wings, compact dark canopy, dorsal fin and lit rear engines are
an original Three.js interpretation of the 1989 *Space Rogue* Dart
recognition-guide silhouette. The NPC is available in both 3D and stereo
SBS views and retains existing hit detection, AI, selected-target ring,
combat damage, destruction, and authoritative deterministic respawn.
Only one Dart can be present at a time; after destruction it respawns
following the existing three-second test-sector delay. A broader,
event-driven spawning system remains future work.

Reference: 1989 *Sunracer Owner's Guide and Navigation Manual*,
Traveller's Recognition Guide p. 32:
https://cdn.steamstatic.com/steam/apps/569200/manuals/space_rogue_manual.pdf#page=36

Documented original Dart: Pirate/Fighter, orange, length 12m, 16t,
armor 245, Garnet laser (10 mw/s), SM-1 missile, Fwd-2 shields,
10% ECM, Borelle High Performance propulsion, acceleration 0.30g,
turn rate 45 degrees/sec.

Implemented now: **245 hull** (mapped from documented armor), **120
general shields**, 0.6 shield absorption, 210 world units/sec,
35 laser damage, 420 range, 1.2s cooldown, 900 detection radius.
The latter combat/flight values are *provisional*, not copies of the
1989 weapon/directional-shield model. SM-1, ECM and forward-only shields
are not implemented yet.

### Solar System Atlas V1 (2026-11-02)

Press **M** to open the Atlas. The first/main view is now a readable
**Solar System** catalog containing **Sun, Mercury, Venus, Earth, Mars,
Jupiter, Saturn, Uranus, Neptune and Pluto** (Pluto is correctly
identified as a dwarf planet). Click a body in the orbital diagram or
the right-side list for its mean solar distance in AU and orbital
period. **Full system** and **Inner planets** provide two levels of
detail. The chart's orbits and relative distances are intentionally
compressed, and drawn orbital phases are *illustrative*, not calculated
current positions or a navigable simulation.

The existing, fully functional **Sector 1-1** XYZ waypoint/helm
planner remains a separate tab. Changing map levels or inspecting a
celestial body does NOT plot a route or transmit a command to the
server. Existing NPC AI, flight, 3D/SBS cockpit and player combat remain
unchanged. This establishes the system-vs-local navigation UI boundary
ahead of server-owned star-system regions, real ephemeris/celestial
coordinates, travel, stations and an encounter director.

Presentation modules:
- `apps/darkorbit_web/assets/js/game/solar_system.mjs` — Solar System
  catalog; star/planet/dwarf classification, mean AU, orbital period and
  schematic chart projection
- `apps/darkorbit_web/assets/js/game/solar_atlas.mjs` — SVG orbital
  rings, selectable object markers, information pane
- `apps/darkorbit_web/assets/js/game/navigation_computer.mjs` —
  system/sector tab orchestration and isolation of existing helm
  commands

Astronomical references:
- https://science.nasa.gov/solar-system/planet-sizes-and-locations-in-our-solar-system/
- https://science.nasa.gov/solar-system/solar-system-facts/
- https://science.nasa.gov/dwarf-planets/pluto/

### Default session entry: Solar System Atlas (2026-11-02)

Opening `/play` now presents the **Solar System Atlas** immediately,
rather than dropping the player into the Sector 1-1 combat cockpit.
The map is rendered as the page's initial state, and the browser
opens the Atlas controller before joining the Phoenix world channel.
The Sun, eight planets and Pluto can be inspected without initiating
flight. The existing cockpit remains accessible via **Return to
cockpit**, **M**, or **Esc**; the Atlas can be reopened with **M**.

This is a **starting-screen change**, not yet a full encounter-system
change: the Sector 1-1 simulation and its single Dart NPC still run
behind the map. Building an event-driven encounter director and an
appropriate noncombat staging area remains future work.

### Peaceful Atlas login and SOL transit V1 (2026-11-02)

The game now **starts with zero NPCs** in Sector 1-1, not a Dart
already attacking the player behind the Atlas. The default
`Core.World.MapServer` retains NPC definitions but does not materialize
them at startup. Only a server-authorized
`Core.World.start_encounter("dart")` command creates the Dart.
It is **not exposed as a client channel event**, and production
encounters no longer use the old three-second automatic respawn.
Legacy combat tests can opt in to initial NPCs and automatic respawn
explicitly.

The Solar System Atlas now has a working **Set course** action:
select Mercury through Pluto (not the Sun), press Set course, and
watch the server-owned transit status and schematic travel marker.
The original 12–120-second prototype times have been superseded by
real-time sublight interplanetary cruise (see V2 below).
Arrival updates the pilot's current solar destination from Earth to
the selected body. Aborting returns to the departure *region*
because V1 does not yet model free flight between orbital positions.
The state machine is supervised and session-authorized. A pilot's
destination cannot be spoofed by another player's client input.

The new modules in `apps/core` are:
- `Core.Universe.Sol` — authoritative Sol destination catalog
  (body identity, type and mean heliocentric AU);
- `Core.Universe.Navigation` — supervised independent system
  travel FSM with Earth as initial location, travel progress, abort,
  arrival and world event delivery.

`DarkorbitWeb.WorldChannel` provides `solar_set_course` and
`solar_cancel_course` intentions on the authenticated connection,
and sends the initial `solar_navigation` snapshot with every
successful join. SOL progress broadcasts are per player; the client
uses only the matching authenticated player id.

**Current scope:** No orbital simulation, moving planets, real
intercept/trajectory calculation, physical movement of the cockpit
ship between planetary sectors, persistence across full server
restarts, or random encounter generation. Sector 1-1 still remains
a separate local tactical flight view. We can connect it later to
the server's solar navigation region as new planetary local sectors
and an encounter director are built.

### Living universe V1 — scheduled neutral traffic (2026-11-03)

**Meridian-01** is the first persistent *runtime* civilian vessel in SOL.
`Core.Universe.Traffic` assigns it a stable ID, independent faction, a
scheduled Earth → Mars machinery delivery, a 45-second dock visit, and a
return Mars → Earth voyage carrying refined minerals. The freighter
advances on the same authoritative one-second system clock as player
voyages **even without any connected player**. A player cannot spawn,
redirect or stop it by joining a session or opening the Atlas.

`Core.Universe.Navigation` derives contacts from Euclidean distances in
compressed system **game-km**, with a provisional 2,000,000 game-km
sensor radius. Contact snapshots are pilot-position-specific; the
`WorldChannel` forwards those snapshots only to the authenticated pilot.
The Atlas's **SENSOR TRAFFIC** panel lists in-range non-hostile vessels
and provides **Hail freighter**. Hailing revalidates sensor range on
the server and returns its purpose and cargo manifest, without altering
the route. Unknown/out-of-range hails are rejected. No browser-supplied
player ID or ship coordinates are trusted.

This is **not** a tactical encounter spawn and not yet a trade inventory
exchange. It does not create a `Core.NPC.Entity`, engage combat, pause
interplanetary travel or move a ship into Sector 1-1. Strategic vessel
identity/route continuity survives player disconnects **within the same
server process**; a full server restart currently resets this seeded
freighter. Next: durable world snapshots, shared tactical encounter
handoffs and consequences from piracy, rescue and trade.

Tests: `mix test apps/core/test/core/universe/traffic_test.exs
apps/core/test/core/universe/navigation_test.exs
apps/core/test/core/world/world_test.exs` (from umbrella root).

### Planetary cockpit visuals V1 — large Venus approach (2026-11-03)

The **3D and SBS cockpits now show the actual current/target SOL planet**
rather than a miniature sphere inside the old sector map. A new
`Core.Universe.PlanetaryView` derives an authenticated, visual-only view
from server-owned SOL navigation progress and actual planetary radii
(Venus mean radius **6,051.8 km**). Its `planetary_view` snapshot has
`body_id`, `radius_km`, `visual_distance_km`,
`angular_diameter_deg`, and a preview stage.

`PlanetaryBody` draws a cloud-textured, lit planet and atmospheric halo
in the existing Three.js cockpit, using a fixed 900-unit camera-relative
display distance and a matching projected radius. This **preserves
angular size** in both normal 3D and SBS without increasing the original
3,000-unit camera clip plane or corrupting laser/NPC depth and physics.
Stars render behind the planet. The planet's bearing is anchored on
first appearance so a pilot may later turn the cockpit away from it.

During Earth → Venus cruise, Venus begins at 1.5° across and becomes
steadily larger as course progress increases; at arrival it occupies
**65°**, nearly the entire 70° vertical cockpit view. The same preview
exists for Earth and other navigable SOL planets. A small cockpit label
clearly identifies the selected planet, angular size and **visual preview**
status. There are no external planet textures or network requests.

**Scope:** these are artistically staged approach/orbit *visuals* in
compressed SOL coordinates, **not** true orbital locations, collisions,
gravitational or atmospheric physics, or the ability to physically fly
down to a planetary surface. On arrival the current tactical map remains
unchanged; local throttle will not yet change orbital altitude or planet
apparent size. Proper shared planetary coordinate frames and travel
handoffs are the next milestone.

Because SOL voyage state is currently in memory, restarting the game to
load this build returns pilots to Earth. Earth is visible immediately;
to see Venus grow, set a new course to Venus and return to the cockpit
with M or Esc while cruise continues. No change to cruise lockouts.

Test targeted changes from `apps/core` with
`mix test test/core/universe/planetary_view_test.exs
test/core/universe/navigation_test.exs`, and frontend with
`npm test --prefix apps/darkorbit_web/assets` from the umbrella root.

### Interplanetary cruise V2 — real-time sublight travel (2026-11-02)

The game now implements two **mutually exclusive propulsion regimes**:

- **Conventional cockpit flight:** the existing slow, precise 3D flight
  dynamics used for local maneuvering, combat, and eventual docking.
- **Sublight interplanetary cruise:** a server-authoritative constant-speed
  navigation mode engaged from the Solar Atlas. It moves through SOL in a
  separate compressed system-level coordinate space at **65,000 game km/s**,
  numerically below the configured light-speed bound. It is not FTL.

**Time is not accelerated for any player.** Each server navigation tick
advances every active voyage by the same real-time second; distance depends
on drive speed. The per-pilot SOL navigation state exposes the authoritative
`position_km`, `propulsion_mode`, `travel_distance_km`,
`distance_travelled_km`, `cruise_speed_km_s`, and a countdown ETA.

SOL uses the planets' real **reference AU** values but a non-linear compressed
**game-kilometer** geometry for playable travel times. Its angular placements
are fixed schematic anchors, not current celestial positions. It would be
incorrect to calculate physical velocities or astrophysical travel times
directly from the AU catalog.

Sample initial timings from Earth at the default speed:
- Venus: 2m 56s; Mars: 4m 20s; Jupiter: 9m 56s
- Saturn: 12m 22s; Neptune: 15m 32s; Pluto: 21m 20s

Cockpit course, flight, targeting, and weapon requests are rejected
server-side while a sublight voyage is active. On engaging a voyage, the
local autopilot and combat target are cleared. The 3D client displays a
flight-lock notice if opened during cruise. Journey state, progress, and
ETA are shown on the Solar Atlas.

**Not yet implemented:** cockpit motion integrated with the system position;
arrival into an actual planetary local sector with randomized safe approach;
physics-based acceleration/deceleration, true orbital ephemerides, planetary
interception, interdiction/encounters, or database persistence across game
server restarts. The V2 abort command still returns to the departure region
until we introduce a playable deep-space local frame.
