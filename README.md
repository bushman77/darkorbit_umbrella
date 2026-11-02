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
Space is reserved for a future single-shot rocket and currently reports that
the action is unavailable. The server validates each intention and broadcasts
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
**Q/E roll left/right**, **= accelerate**, and **- decelerate**.
Holding the throttle keys ramps in 10% steps; signed throttle can cross
zero into reverse. **Ctrl+E** switches Cruise (assisted velocity) and
Newtonian (momentum-preserving thrust). **F** releases held attitude
controls. The flight HUD shows heading, pitch, roll and speed.
**M** opens the navigation atlas for optional XYZ autopilot routes.

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
roll and =/- for signed throttle; X is intentionally unassigned.

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

In the 3D or stereo cockpit, **Space** fires the currently ready X1
laser along the *ship's present nose direction*. Holding Space fires
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

Manual Space fire now launches two simultaneous, genuine 3D rays from
physically symmetric wing emitters. The muzzles belong to the ship's
server-owned quaternion orientation, so yaw, pitch and roll move the
mounts with the craft. Each ray can hit or miss independently; NPCs
within range receive server-authoritative shield/hull damage, and
collisions are replicated to all clients as paired impact endpoints.
A single Space activation uses one cooldown and the original total
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
A selected target is *not* automatically hit by manual Space fire:
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
