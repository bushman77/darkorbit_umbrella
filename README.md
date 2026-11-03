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
is moving, but now detects inactivity after approximately **25ms** instead
of 55ms. An independent browser timer and a render-frame fallback send a
zero yaw/pitch command immediately, bypassing ordinary motion command
throttling. While moving, packets are capped at roughly 40 per second.
The server zeros the mouse's angular velocity **on receipt of neutral input**,
rather than waiting for its next 100ms simulation tick. Pointer-locked local
camera interpolation is also reduced from 85ms to 25ms; remote players
and keyboard steering retain their usual smoothing and braking.
These are best-effort responsiveness improvements, not a guarantee of an
instantaneous physical stop: browser scheduling, packet transit, a server tick
that has already run, and rendering frame cadence can still add latency.
Translational flight inertia is unchanged. If Firefox releases
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

**Historical V1 scope:** the initial implementation provided only staged
planet visuals and had no collision or separate orbital maps. These
limitations were subsequently addressed in part by Planetary Orbital
Regions V2 and Fatal Planet Impact V1 (documented below). True gravity,
atmospheric flight and surface landings are still not implemented.

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


### Planetary orbital regions V2 — directional arrival and shared maps (2026-11-03)

**All SOL destinations now have a planetary cockpit view and an arrival
region.** After a voyage completes, the server uses the previous SOL region,
destination and voyage identity to compute a direction-dependent orbital
entry point. The ship appears on the **side of the destination planet it
approached from**, at a safe radial offset, with its nose facing the planet.
A small deterministic offset per pilot/voyage reduces overlapping spawns.

`Core.Universe.OrbitalEntry` assigns a separate, server-supervised
`MapServer` to Mercury, Venus, Mars, Jupiter, Saturn, Uranus, Neptune and
Pluto (`sol:<body>`). Their local maps are each 400,000 × 400,000 units,
with a ±200,000 vertical range, and use **provisional local kilometres**,
not SOL's compressed cruise game-kilometres. Players sharing a planetary
region share its map; pilots at *different* planets cannot see or target
each other across maps. Current gameplay now assigns Earth to the same
real-radius orbital model as other planets (`sol:earth`). Legacy Sector
`1-1` remains only for isolated combat/channel tests.

The new orbital maps carry the corresponding planet's real mean radius
and a 1.08×-radius server-owned safety boundary. Manual flight stops
there instead of passing through the planet. The cockpit planet is
positioned toward the map's authoritative planet centre, and its
apparent size updates as the ship's distance changes. This is a
planetary-relative tactical **staging** system: no orbital gravity,
terrain, docking, atmospheric entry, or surface landings yet.

`DarkorbitWeb.WorldChannel` enforces the server-resolved region on
join, publishes SOL navigation to a dedicated shared topic, and pushes
`world_region_changed` when the voyage arrives. The browser leaves
its old channel, re-enters the destination region and refreshes its
sector chart. A client cannot choose an arbitrary map or spawn.
The four old noninteractive test asteroids are removed; the starfield
now follows the camera in the much larger orbital maps.

**Compatibility:** the first live login at Earth now enters `sol:earth`
with the same safe approach-scale spawn and fatal planet volume as Venus.
The old `(1000,1000)` Sector `1-1` spawn persists only behind a
`config/test.exs` fixture switch. Full server restarts still reset
the in-memory SOL voyage and orbital entry; pilot hull/ship state is
not yet carried durably across region changes. These are staged
orbital regions, not gravitationally simulated orbits.

**Verification** from the umbrella root:
```sh
cd apps/core
mix test test/core/universe/orbital_entry_test.exs test/core/universe/navigation_test.exs test/core/world/flight_dynamics_test.exs test/core/world/world_test.exs
cd ../..
npm test --prefix apps/darkorbit_web/assets
mix test apps/darkorbit_web/test/darkorbit_web/channels/world_channel_test.exs
```

### Fatal planetary collisions V1 — hard approach limit (2026-11-03)

Planet approach is now dangerous, as in the original game: **getting too
close destroys the spacecraft**. Every SOL planetary region (including Earth)
uses its real mean radius with a provisional **8% collision buffer**.
For Venus, the lethal boundary is approximately **6,536 km from its
centre** (radius 6,051.8 km). The normal directional spawn remains
farther away at about **1.861 planetary radii**.

`Core.World.PlanetaryCollision` tests the **entire 3D movement segment**
from the previous position to the next, preventing high-speed tunneling
through a planet. `Core.World.MapServer` applies the same check to
manual thrust and local plotted autopilot movement. A collision sets
the ship to `:destroyed`, zeroes hull/shields and velocity, clears
navigation and targeting and emits one `entity_destroyed` event
containing `reason: :planetary_collision` and the planet ID. The
cockpit displays a clear planetary-impact message and releases pointer
capture. No NPC receives kill credit from a planetary crash.

**No automatic player respawn is implemented yet**, matching the
existing destroyed-player behavior. Planet collisions are disabled
for the isolated legacy `1-1` test fixture; normal Earth gameplay
uses `sol:earth` and the same collision rules as Venus. This is a gameplay collision volume, not
atmospheric re-entry simulation, gravitational physics, or terrain.

Run from the umbrella root:
```sh
cd apps/core
mix test test/core/world/planetary_collision_test.exs \
  test/core/world/planetary_impact_integration_test.exs \
  test/core/world/flight_dynamics_test.exs
cd ../..
npm test --prefix apps/darkorbit_web/assets
```


### Planetary proximity alerts V1 — visual approach warnings (2026-11-03)

The game now warns **before** a fatal planetary impact in each orbital
region (Mercury, Venus, Mars, Jupiter, Saturn, Uranus, Neptune and Pluto).
The server computes the 3D distance to the body's collision boundary:
**CAUTION** at 1.55× the lethal radius, and **CRITICAL** at 1.20× the
lethal radius. The lethal collision itself remains 1.08× the planet's
mean physical radius. These are provisional gameplay alert distances,
not a physically simulated atmospheric re-entry corridor.

On Venus the rounded radial distances are approximately:
- CAUTION starts at **10,131 km from the centre**, about **3,595 km**
  before the fatal boundary.
- CRITICAL starts at **7,843 km from the centre**, about **1,307 km**
  before the fatal boundary.
- IMPACT occurs at **6,536 km from the centre**.

The normal approach-based arrival spawns outside CAUTION. New cockpit
warning bands appear in amber/red, with live distance **to the lethal
collision boundary**. A stereo-correct warning is drawn in the SBS 3D
cockpit HUD; the flat banner is hidden in SBS to prevent eye strain.
`Core.World.PlanetaryProximity` emits events only on changes between
`:clear`, `:caution` and `:critical` (including retreat). Per-ship
current warning data also travels in `planetary_warnings` on every
authoritative world snapshot, allowing an already-nearby pilot to
reconnect and immediately see the correct warning. No client-side
distance estimate can change gameplay or fabricate death.

This milestone has no collision sound, gravity, rescue, or automatic
respawn. The legacy `1-1` combat test fixture still has no planet volume;
normal Earth gameplay does.

Test from the umbrella root:

```sh
cd apps/core
mix test test/core/world/planetary_proximity_test.exs \
  test/core/world/planetary_impact_integration_test.exs \
  test/core/world/planetary_collision_test.exs
cd ../..
npm test --prefix apps/darkorbit_web/assets
mix assets.build
```

### Unified planetary hazards for every SOL destination (2026-11-03)

The planetary rules now cover **all nine navigable SOL bodies**, including
Earth and dwarf planet Pluto. The single authoritative `Core.Universe.Sol`
catalogue owns each body's mean physical radius. `Sol.planets/0` supplies
`Core.Universe.OrbitalEntry.planet_maps/0` with **every registered body**;
each gets a shared collision-ready `sol:<body>` region, an automatically
safe, approach-direction-derived spawn, 1.08× fatal collision radius,
1.20× critical and 1.55× caution zones relative to the fatal radius,
and server-driven `:entity_destroyed` consequences. Current maps are
400,000 local units wide; the generator enlarges maps for oversized future
planetary radii.

**Earth now uses `sol:earth` in live gameplay**, including the very first
login; its planet moves in the cockpit as a real orbital-relative backdrop
and it can destroy ships. `1-1` is retained solely as a legacy combat
test fixture through `config/test.exs`'s
`legacy_test_earth_sector` flag. The normal application configuration
does not enable that exception.

The cockpit's map-ID validator and procedural planet texture generator
now accept well-formed future planet IDs without a client-code allowlist.
A newly added SOL planet still requires registering its navigable orbit,
radius and name in `Core.Universe.Sol`, and inclusion in any Atlas catalog
used for selection, but **does not require new collision or warning code**.
A completely different star system still needs its own system catalogue
and cross-system routing; wormhole mechanics are not implemented.

Targeted regression suite from the umbrella root:

```sh
cd apps/core
mix test test/core/universe/sol_test.exs \
  test/core/universe/orbital_entry_test.exs \
  test/core/universe/planetary_view_test.exs \
  test/core/world/all_planet_regions_integration_test.exs \
  test/core/world/planetary_collision_test.exs \
  test/core/world/planetary_proximity_test.exs \
  test/core/world/planetary_impact_integration_test.exs
cd ../..
mix test apps/darkorbit_web/test/darkorbit_web/channels/world_channel_test.exs
npm test --prefix apps/darkorbit_web/assets
mix assets.build
```


### Living-universe flyby encounters V1 — observable in the cockpit (2026-11-03)

Six **pre-existing, autonomous** SOL vessels now run the shared-world
traffic loop: Meridian-01 freight Earth–Mars, Vesper-02 express courier
Earth–Venus, Wayfinder-04 Earth–Mars survey vessel, Sentinel-07 patrol
Venus–Mercury, Aurora-12 Mars–Jupiter freight and Sable-18 Jupiter–Saturn
independent trader. Each has a fixed identity, cargo manifest, purpose,
initial route phase, and repeated outbound/return routes. No player action
creates a vessel. Vessel movement proceeds every second even without
players logged in, and schedules vary relative to pilot departure times.

`Core.Universe.Encounters.nearest/2` resolves a **close pass within
650,000 game km** while a pilot is between 5% and 95% of an actual
interplanetary cruise. This is stricter than the 2,000,000 game-km
sensor/hail radius. Only moving traffic is eligible. The authoritative
navigation process emits `:solar_encounter_started` once per vessel
voyage for each pilot, and exposes the current `encounter` in the
per-pilot navigation snapshot. This does not stop or redirect travel,
and no client may invent an encounter or reveal cargo just by scanning.

In normal 3D and SBS cockpit mode, a close-pass sensor projection shows
a visible 3D ship from the traffic's **actual route-relative bearing**.
Its apparent scale grows as separation decreases. This is a visual
staging contact, *not* a tactical combat NPC, local-kilometre position,
targetable hitbox or collision body. Normal 3D also shows a Hail/Dismiss
panel; SBS renders the notification in the stereo cockpit HUD, and
hailing remains available through Solar Atlas. Hails use the already
server-validated `solar_hail` endpoint to reveal purpose and manifest.
The encounter disappears on separation, and the voyage continues.

**Repeatable verification after a fresh world restart:** plot an
Earth → Venus course and watch the cockpit around the middle of
the approximately three-minute cruise. Vesper-02 begins about 22% along
the Earth→Venus route at world start and moves at 42,000 game km/s;
your 65,000 game km/s drive catches up approximately 109 seconds after
a *fresh* launch. This is a test opportunity, not an invariant scripted
spawn: traffic continues in the background, so encounter timing changes
if you depart later. Other routes have independent opportunities.

**Not yet included:** intentional tactical intercept/stop, 3D collision
or combat with traffic, piracy, hostile skirmishes, trade transfer,
persistent cargo database, or restart-proof voyage states. These need a
shared physical encounter-map handoff; a visual flyby never grants
tactical combat authority.

Targeted tests from the umbrella root:

```sh
cd apps/core
mix test test/core/universe/traffic_test.exs \
  test/core/universe/encounters_test.exs \
  test/core/universe/navigation_test.exs
cd ../..
mix test apps/darkorbit_web/test/darkorbit_web/channels/world_channel_test.exs
npm test --prefix apps/darkorbit_web/assets
mix assets.build
```

### EncounterDirector V1 — server-owned contact policy (2026-11-03)

`Core.Universe.EncounterDirector` now classifies real close-pass contacts as
`:neutral_flyby`, `:patrol_attention` or `:hostile_contact`. The director
reuses the existing traffic/encounter geometry; it never spawns vessels or
interferes with cruise. Patrol attention requires a faction-owned patrol
within its own Zone of Control and server-provided standing <= -25.
Sentinel-07 is explicitly a Venus patrol; the other five scheduled vessels
remain independent and neutral.

The navigation GenServer attaches classification to pilot-specific encounter
snapshots and the one-time `solar_encounter_started` event. The regular 3D
cockpit panel distinguishes non-hostile, patrol-attention and hostile
contacts without implying actual inspection or combat. All sightings are
still strategic flybys; SBS uses the existing flyby visualization.

**Boundaries:** The player reputation map is a server-side integration
fixture, not yet a durable faction-standing ledger. Existing seed traffic
remains non-hostile by default. No tactical encounter creation, forced
interception, combat consequences, new client commands, or database state
are introduced. A separate shared tactical handoff is still required.

Regression tests added for zone/standing boundaries, hostile precedence,
non-spawning semantics and a hostile per-pilot navigation event. Existing
courier, survey, travel and client tests remain applicable. Automated test
execution and manual cockpit verification were **not performed** in this
editing environment (Elixir/Mix runtime unavailable).

To verify from the umbrella root:

```sh
mix test apps/core/test/core/universe/encounter_director_test.exs \
  apps/core/test/core/universe/encounters_test.exs \
  apps/core/test/core/universe/navigation_test.exs \
  apps/core/test/core/universe/traffic_test.exs
mix test apps/darkorbit_web/test/darkorbit_web/channels/world_channel_test.exs
npm test --prefix apps/darkorbit_web/assets
mix precommit
```


### Encounter decision hold V1 — visible choice during cruise (2026-11-03)

A real strategic close pass now **holds the pilot's interplanetary course**
at the detected game-km position. The authoritative SOL navigation server
stores a `pending_encounter` on that pilot's voyage and keeps its elapsed
travel time, position, and ETA unchanged on subsequent ticks. This is a
per-pilot hold, **not** a global pause: other pilots, NPC schedules and the
SOL clock keep advancing.

A centered `SOL / ENCOUNTER DETECTED` dialog appears above the Atlas or
normal cockpit. Stereo SBS presents one matching dialog in each eye.
The options are **Hail vessel** (existing server-validated communications,
keeps the ship held) and **Ignore / Resume course** (authenticated server
command that releases the hold without resetting the route). The modal
cannot be dismissed just by Escape or opening the Atlas. Reconnecting to
the server restores the exact pending encounter. Invalid encounter IDs
and unsupported actions are rejected. The course abort action is blocked
while an encounter decision is pending.

The contact's reported distance is its distance **at detection**; live
NPCs continue moving. A hail may become unavailable if a vessel leaves
sensor range, but the pilot can always resume the voyage. This V1 is a
dialogue hold, **not** an NPC braking manoeuvre, tactical interception,
combat instance, trade transfer, or faction consequence. No randomly
spawned enemies are introduced.

Automated regression tests were added for a held Earth–Venus courier,
server-side pause/resume and spoofed-decision rejection. Existing travel
completion tests now explicitly resolve genuine encounters when they
occur. Test execution and visual browser verification have not been
performed in the editing environment.

Suggested checks from the umbrella root:

```sh
mix test apps/core/test/core/universe/navigation_test.exs
mix test apps/darkorbit_web/test/darkorbit_web/channels/world_channel_test.exs
npm test --prefix apps/darkorbit_web/assets
mix assets.build
mix precommit
```

To see the dialog, start from a fresh world process, plot Earth → Venus
and remain in the Atlas or cockpit. The Vesper-02 courier is initially
ahead along the route, so a close pass should occur roughly **81 seconds**
after leaving Earth if traffic has not already moved on. Later departures
change encounter opportunities; a voyage is not guaranteed to meet the
courier at that time.

### Development headset access (2026-11-03)

During development, Phoenix/Bandit binds to `0.0.0.0:4000` by default, so a
paired SBS headset/phone on the **same trusted LAN** can access the laptop at
`http://<laptop-LAN-IP>:4000`. The loopback host `localhost` still works on
the laptop but cannot be used from a separate device.

Run normally: `iex -S mix phx.server`. To deliberately restrict the dev server
to the laptop, launch with `DARKORBIT_LOOPBACK_ONLY=1 iex -S mix phx.server`.
This dev configuration is not intended for untrusted/public networks;
`check_origin: false` remains enabled for development and should not be
used for a public deployment. Firewalls and Wi-Fi client isolation can still
prevent headset access even when Bandit listens on all interfaces.

Configuration change inspected on the `sbs` branch. Browser/HMD connectivity
has not been manually verified.


### Encounter popup delivery in laptop and paired SBS headset (2026-11-03)

The laptop cockpit now handles the authenticated `solar_encounter_started`
notification directly so the server-held encounter decision opens immediately.
The normal navigation snapshot still restores the popup when reconnecting.
The modal covers both Atlas and cockpit until the pilot selects **Hail vessel**
or **Ignore / Resume course**, and the Atlas is made inert underneath it.

A paired **phone headset runs a different, read-only Phoenix channel**. When
in cockpit mode it now subscribes to SOL and receives only its authenticated
pilot's minimal encounter display status; it shows a matching stereo
contact-hold notification in each eye. No contact cargo, reputation data,
other pilot's encounter IDs, or ship commands are delivered to the headset.
The phone displays a prompt to make the Hail/Resume choice on the laptop.
In Atlas/standby mode the headset remains black as designed.

The ship remains paused by the authoritative navigation process while a
decision is pending. Other ships and the SOL clock keep moving. The
encounter is still a strategic decision, not physical tactical interception.
The HMD overlay is informational, not a VR controller.

Added `helmet_encounter_view_test.mjs` and new helmet channel event
privacy tests. Execution of Mix, JS and browser/HMD manual verification
remains outstanding at this commit.

### Reliable procedural SOL encounter traffic (2026-11-03)

Previously a voyage could have no encounters unless it physically crossed one
of six continuously moving scheduled ships, within 650,000 game-km. Vesper-02
could be gone from the Earth–Venus route by the time a player launched.

For the current gameplay prototype the world supervisor now launches one
**server-owned shared traffic vessel per accepted interplanetary course**.
The ship travels on a real opposing route, not as a client-only popup or
tactical NPC spawn. The server randomly selects an independent trader,
faction patrol or hostile raider and a viable position on the lane. Existing
six scheduled vessels continue independently. The new ship is visible to
other pilots through the same traffic simulation.

The real close pass activates the existing pilot-only navigation hold and
Hail / Ignore–Resume popup. The radio channel stays established for the
exact pending encounter even if that vessel subsequently moves outside
short-range sensors. Hailing other ships still requires sensor proximity.

The world supervisor's playtest launch chance is 1.0, so an attempted
shared contact occurs on each voyage; a bounded 32-ship procedural pool
can skip launches if full. Generated vessels expire after 15 minutes of
world simulation. Isolated Navigation tests default to 0.0 to keep their
original scripted fleet checks deterministic. Before production, reduce
the launch chance and balance faction/ZOC/route traffic density.

Hostile contacts are informational until the tactical combat handoff is
implemented. Process restarts still reset strategic fleet state.

Run the SOL traffic and navigation Mix tests, the Phoenix channel tests
and `mix precommit`. A live playtest should start from Earth, set a course
to Venus, encounter a real trader/patrol/raider at roughly 20–40% journey
progress, Hail, then Resume without resetting the route. Manual/automated
test execution has not been performed in the editing environment.



### SOL close-pass -> tactical cockpit handoff (2026-11-03)

Hostile raiders and faction patrol attention encountered during interplanetary
travel now offer **Engage / Enter combat** alongside **Hail vessel** and
**Ignore / Resume course**. Neutral contacts remain hailable/ignorable.
Only the authenticated pilot with the exact pending encounter ID can engage.

Engage creates an authoritative, live Dart-class tactical opponent (shown
under the strategic contact's call sign, e.g. Corsair-1) beside the pilot's
ship in the existing planetary orbital combat map. This is the first
playable handoff, not yet a dedicated mid-space battle instance. The pilot's
SOL voyage remains held at its previous position and elapsed time; other
pilots' journeys and the traffic simulation continue.

The Atlas closes into the 3D/SBS cockpit and conventional controls and
weapons are enabled **only** for the pilot's active tactical encounter.
A small tactical banner offers **Retreat / Resume course**. A kill must
be verified by the map's authoritative NPC state before the SOL navigation
server releases the hold on victory; remote clients cannot claim a kill.
Retreat removes the encounter NPC, clears stale target locks and resumes
the original voyage. A failed spawn rolls back to the existing decision
modal rather than losing the encounter.

The paired phone HMD's read-only channel now follows the pilot's *actual*
orbital region rather than always subscribing to legacy Sector 1-1. It
still cannot submit gameplay commands. The current planet remains visible
in the laptop cockpit during tactical play so planetary collision
hazards aren't hidden by the previous destination's cruise preview.

This is a prototype shared-map tactical handoff. It does not yet preserve
a physical mid-voyage origin in a separately instantiated combat arena,
translate strategic trader types to distinct NPC models, persist live
encounters across a full server restart, or provide economic penalties and full recovery UX. When the pilot is
destroyed in combat, the server cancels the SOL voyage and clears that
encounter; reconnecting creates a new ship at the departure region. Credit
loss, equipment damage and a seamless respawn screen remain separate milestones.

Test with a fresh Earth -> Venus voyage that meets a Corsair raider. Click
**Engage / Enter combat**, close on the Dart-class enemy, destroy it or
press Retreat; the Atlas should return with the original course progressing.
The current running server must be restarted after pulling this commit.
Run core World tests, Core Navigation tests, Phoenix World/Helmet channel
tests, JavaScript assets tests, then mix assets.build. Editing environment
has not run Mix or physical HMD testing.

The tactical Dart is rendered with the existing swept-wing Dart Three.js model,
not a generic orange placeholder. The NPC targets its owning pilot only;
other pilots may observe the shared orbital-map fight.


### Player-initiated attacks on neutral encounters (2026-11-03)

The held SOL encounter dialog offers three choices for a neutral vessel such
as Harbor-1: **Hail vessel**, **Attack vessel**, or **Ignore / Resume course**.
Previously only hostile raiders and patrol-attention contacts could use the
tactical cockpit handoff. The server now permits a pilot to initiate combat
against their own authenticated, currently pending neutral flyby; the client
cannot invent an encounter or spoof a target. Existing hostile encounters
still show **Engage / Enter combat**.

Entering combat against a neutral vessel uses the same currently available
3D Dart-class placeholder opponent and the existing paused-voyage handoff.
Unlike a raider, the neutral opponent patrols without acquiring the pilot
as a target. It begins defending itself **only after an authoritative hit**
from either a targeted attack or a manual twin-laser burst. Pressing the
Attack button is not itself a laser hit. The original shared SOL voyage
remains held until verified victory, retreat, or defeat.

This first implementation has **no reputation penalty, criminal status,
loot, or cargo transfer** yet, and the neutral freighter still uses a Dart
tactical model until proper trader hull assets are implemented. These
consequences and visuals must be designed separately, rather than pretending
they exist. The six scheduled ships and generated traffic continue their
normal shared SOL movement.

Regression coverage includes an ordinary neutral scheduled encounter,
a genuine procedurally generated Harbor-1 contact, prevented pre-hit
aggression, first-hit retaliation, and exact-encounter session authorization.
Mix tests and live headset/browser verification were not run here.


### Distinct Scow merchant vessels (2026-11-03)

The original Space Rogue (1989) recognition guide describes the Scow as a
blue, 23-metre, 74-tonne small merchant freighter with a 10-tonne cargo
capacity, 210 armor, a turreted Garnet laser (10), an aft shield and no
missiles. The live system now registers **Scow** as a distinct NPC ship type
alongside the Dart fighter. The original's 210 armor and 10-damage beam are
represented by max hull and laser damage. Other ship physics are balancing
approximations because the current combat model lacks directional shields,
per-class acceleration and cargo-tonnage slots.

Scow template stats: hull 210, generic shields 45, laser 10, movement 105
game units/second, attack range 380 units, fire cooldown 1800 ms. Compare
Dart's hull 245, shields 120, damage 35 and movement 210 in the current
prototype. The Scow is deliberately the slower civilian target and is not
automatically spawned into the legacy test sector.

Every live independent trader, scheduled commercial freighter and courier
is identified as a Scow in shared SOL traffic. Contacts carry that
authoritative type into the held encounter and authenticated tactical
handoff, spawning `solar-scow-<player id>` with genuine Scow hull and
weapon values. Raid patrol/raider combat uses the existing Dart template.
Traffic schedules and cargo manifests remain unchanged.

A new, original low-poly Three.js Scow is rendered in both laptop and SBS
headset through the same 3D model-selection path: blue rounded cargo bow,
wide rear cargo deck, sectional cargo holds, dorsal turret and twin engines.
No third-party game art is embedded. The tactical opponent displays its
real callsign and Scow geometry, never a generic Dart.

Scows currently start passive on player-initiated attack and fight back
only after receiving a confirmed hit (the existing neutral-contact rule).
Proper captain decisions to flee, surrender cargo or fight in self-defense
and corresponding reputation, loot and trading outcomes remain the next
behavioral milestone. Adding a new ship class alone must not falsely
claim that the original game's surrender/flight logic is already present.

Regression tests cover SOL encounter classification, different Scow
combat stats and render selection for dynamically named Scow NPCs.
Run Core World and Universe Traffic tests, Phoenix WorldChannel tests,
Node assets tests, then assets build. The original source reference is
the published 1989 Sunracer Owner's Guide, recognition guide p. 31.
