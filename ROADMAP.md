# 🚀 Darkorbit Umbrella – Roadmap

## 🎯 Vision
based on https://github.com/yusufsahinhamza/darkorbit-cms
Rebuild a modern, scalable DarkOrbit server ecosystem using Elixir/OTP, replacing legacy PHP CMS-style architectures with:

- Strong domain modeling
- Real-time systems (Phoenix / Channels)
- Deterministic gameplay state
- Atomic economy + equipment systems
- Clean separation of concerns (umbrella apps)

Inspired by:
- Legacy CMS implementations (PHP-based control panels, game logic coupling)
- Private server ecosystems (equipment, PvP, progression loops)
- Goal: production-grade MMO backend

---

## 🧠 Current Architecture (What We Have)

### Core Domains Implemented

#### ✅ Accounts
- Registration
- Session generation
- Player metadata (credits, uridium, level, etc.)

#### ✅ Inventory System
- Persistent player_equipment
- Structured equipment bag:
  - lasers
  - generators
  - drones (future-ready)
- Helpers:
  - laser_count/2
  - add_lasers/3
  - remove_laser/3

#### ✅ Fleet (Ships)
- player_ships per user
- Ownership validation
- Active ship switching
- Starter ship provisioning

#### ✅ Loadouts (Critical System)
- 2 configs per ship
- Slot-based system:
  - ship slots
  - drone slots
- Fixed slot arrays (deterministic layout)

#### ✅ Equipment Engine (Major Milestone)
- Equip / unequip
- Slot validation:
  - bounds
  - capacity (ship-specific)
- Inventory integration:
  - consume on equip
  - return on overwrite
- Atomic transactions via Ecto.Multi

#### ✅ Preferences / Titles
- Player settings
- Titles ownership + selection

---

## ✅ Completed Milestones

### Milestone A — Persistent player domains

- Account registration and authentication
- Inventory, fleet, two ship configurations, preferences, and titles
- Slot-based equipment mutations and starter-ship provisioning

### Milestone B — Persistent-state hardening

- Atomic account provisioning and equipment replacement
- Ownership-scoped mutations, row locks, uniqueness constraints, and database checks
- Concurrent inventory and loadout regression coverage

### Milestone C — Derived stats and authoritative world

- Configurable ship and equipment catalogs
- Pure configuration-aware ship-stat calculation
- Supervised sector `1-1`, sessions, bounded server-owned movement, deterministic ticks, and PubSub events

### Milestone D — Authenticated browser flight

- Credential login, signed game socket tokens, and an authenticated Phoenix world channel
- Canvas 2D sector renderer, original placeholder graphics, interpolated authoritative snapshots, and multiplayer movement events
- Playable development pilots seeded for browser testing

### Milestone D.1 — Continuous mouse navigation

- Single-click destination setting remains available
- Click-and-hold continuously steers toward the pointer at approximately 10 commands per second
- Pointer destinations are recalculated as the camera follows the ship
- Pointer capture, cancellation, focus loss, and hidden-tab cleanup are handled safely
- Near-ship and redundant retargets are suppressed to avoid jitter and unnecessary traffic
- The client still sends destination intent only; boundary validation, position, and speed remain server-owned

### Milestone E — Server-authoritative NPC combat

- Configurable NPC catalog with **one Dart pirate fighter** in the Sector `1-1` demo (replacing the initial three Rift Skirmishers); deterministic respawn keeps one live enemy at a time
- Map-owned NPC movement, hull, shields, targeting, bounded AI, destruction, and tick-based respawning
- Pure range, cooldown, shield-absorption, hull-damage, and destruction rules
- Authenticated target/select/fire channel intentions with authoritative multiplayer combat events
- Right-click and accessible nearest-target selection, target HUD, authoritative toggle firing, laser and hit effects, and explosions
- Catalog-defined Phoenix pulse emitter so existing development pilots can fight without inventory grants or duplication

### Milestone E.1 — Classic combat controls and action hotbar

- Left-click NPC selection uses rendered entity dimensions and consumes the pointer gesture before navigation; empty-space click-and-hold flight is preserved
- Selected and engaged targets are separate authoritative states, with explicit engage/disengage commands and idempotent repeated activation
- The map tick automatically fires the server-defined pulse emitter when range and cooldown rules permit, pauses while out of range, and clears combat across destruction, removal, disconnect, and respawn lifecycles
- Engaged player ships visually face their replicated target independently of movement, then smoothly return to navigation facing when combat ends
- Responsive bottom-center slots `1` through `0` use server-defined action data, with X1 ammunition in slot 1 backed by the ship's server-defined pulse emitter and safe empty placeholders in slots 2 through 0
- Ctrl, number-row keys, click activation, Esc cancellation, active/selected/empty/cooldown states, reserved Space behavior, and input-control/key-repeat guards are implemented

Manual browser verification confirmed navigation, NPC targeting, persistent laser engagement, combat facing, and circular combat maneuvering for Milestone E.1. Broader multiplayer browser validation remains deferred.

### Milestone E.2.1 — Modular cockpit HUD and persistent layouts

- Ship status, target information, and the minimap now use one reusable cockpit-window system with unique identifiers, dedicated drag handles, focus ordering, collapse controls, and a window visibility menu
- Unlock/lock editing, Pointer Events with capture cleanup, keyboard positioning, viewport clamping, reset-to-default behavior, and versioned per-player browser persistence are implemented without changing authoritative simulation behavior
- The previous main-canvas minimap was replaced by one dedicated, resize-aware minimap canvas driven by the existing interpolated world entities and authoritative map boundaries
- The ten-slot action hotbar remains anchored at bottom center, outside the movable window layer, with click, number-row, Ctrl, Esc, reserved Space, and cooldown behavior preserved
- Narrow viewports use a horizontally scrollable cockpit dock instead of free-floating windows, keeping panels recoverable after resize
- Automated coverage exercises drag lock state, collapse, visibility, reset, persistence, malformed storage, clamping, resize mode, pointer cleanup/input isolation, keyboard behavior, reduced motion, and minimap projection/lifecycle

The E.2.1 code and automated verification are complete. Manual browser verification of the new cockpit at the target viewport sizes has not yet been performed.

### Milestone E.2.2 — Interactive and scalable minimap

- Locked-HUD minimap clicks and click-and-hold gestures now submit projected destination intentions through the existing pointer-navigation lifecycle while movement positions, speed, validation, and combat remain server-owned
- Visible minus and plus header controls resize the floating minimap in 40-pixel steps from 192 through 520 pixels, with an additional available-viewport clamp
- Minimap width uses the existing version-1 per-player cockpit storage; older payloads retain their complete layout and receive the 272-pixel default, while reset restores and persists that default
- Narrow viewports keep the horizontally scrollable dock sizing, and the selected floating width is retained for the return to floating mode
- JavaScript regressions cover sizing, automatic persistence/reload, legacy layouts, reset, configured and viewport bounds, responsive docking, continuous minimap steering, combat isolation, and cancellation cleanup
- `mix precommit` passes 84 Elixir tests, `npm test` passes 46 JavaScript tests across 37 top-level cases, the 3-test authenticated page file passes, and `mix assets.build` passes

The E.2.2 implementation and automated verification are complete. Manual browser verification was not performed; the full sizing, reload, responsive-dock, minimap-steering, and combat-preservation flow remains required at the supported viewport sizes.

### Milestone E.2.3 — Server-authoritative laser toggle controls

- `Core.Combat.ActionCatalog` now exposes action ID, type, and activation mode; slot 1 is the toggle-mode X1 ammunition action while the Phoenix pulse emitter remains the separate server-owned weapon and cooldown source
- One serialized world toggle powers both Ctrl and slot-1 activation. Toggle-off preserves `target_id`, clears only `engaged_target_id`, and leaves `next_attack_tick` unchanged; Escape still clears selection and engagement
- `ControlLeft` and `ControlRight` are accepted once per physical key press, held repeats and Ctrl chords are ignored, and Space now reports the reserved rocket action as unavailable without firing
- NPC selection remains independent from firing, destroyed targets clear both states, and a newly selected live NPC can start a fresh engagement
- Hotbar active state and `AUTOFIRE`/`STANDBY` presentation consume authoritative engagement state and action metadata, while canvas pointer-down restores gameplay focus without taking keyboard behavior from cockpit controls or editable fields
- Automated regressions cover direct/slot/alternating toggles, stop/resume, clear and destruction lifecycles, sequential NPCs, cooldown preservation, invalid/empty/unauthorized/destroyed/missing-target safety, both Ctrl keys, held-key suppression, Space reservation, action metadata, and all existing cockpit/minimap/navigation behavior
- `mix precommit` passes 87 Elixir tests, `npm test` passes 48 JavaScript tests across 39 top-level cases, `mix assets.build` passes, and `git diff --check` passes

The E.2.3 implementation and automated verification are complete. Manual browser verification was not performed; Ctrl/X1 alternation, stop/resume with the retained target, Space messaging, focus restoration, and two-browser observation remain required.

---

## 🚧 Next Major Milestones

### 1. Inventory Expansion
- Drone equipment slots
- Ammo system
- Stackable vs unique items

### 2. Ship Stats Engine ✅
- Configurable ship and equipment catalogs
- Two configuration-aware loadouts
- Pure derived stats from equipped inventory

### 3. Combat System (initial PvE slice complete)
- Server-authoritative NPC targeting, damage, cooldowns, destruction, and respawning ✅
- Server-authoritative NPC attacks and player damage ✅
- PvP, ammunition, rewards, and player respawning remain future work

### 4. Map / World Layer (initial player-flight slice complete)
- Supervised starting map (1-1)
- Server-owned player positioning and bounded movement
- Configurable deterministic simulation ticks
- Continuous click-and-hold client navigation ✅
- NPC spawning, AI, combat, destruction, and respawning ✅
- Persistent tick-owned player combat engagement and independent combat facing ✅
- Modular local cockpit layout and standalone minimap rendering ✅
- Server-authoritative minimap steering and persistent bounded minimap sizing ✅
- Atomic server-authoritative Ctrl/X1 laser toggling with retained selection ✅

### 5. Real-Time Layer (movement and PvE slices complete)
- Authenticated Channels and sockets ✅
- Connected-player presence and disconnect cleanup ✅
- Movement synchronization ✅
- Targeting, laser, damage, destruction, and respawn events ✅
- Engagement, disengagement, atomic laser toggling, hotbar activation, and replicated combat-facing state ✅

### 6. Economy System
- Shop / purchases
- Credits vs Uridium balancing
- Loot drops
- Auction system

### 7. Progression Systems
- Experience → leveling
- Rank system
- Skill tree
- Drone leveling

### 8. CMS Replacement Layer
- Phoenix LiveView dashboard
- API-first backend
- Real-time updates

---

## 🧱 Architectural Direction

Principles:
- Persistent account state is authoritative in the database
- Live movement and combat state is authoritative in map processes
- Derived values are computed, never stored
- All mutations are transactional
- Systems are composable

---

## ⚠️ Known Gaps

- The E.2.1/E.2.2 cockpit and minimap still require manual browser verification at 1366×768, 1920×1080, 2560×1440, and mobile-sized viewports
- The E.2.3 Ctrl/X1 toggle, retained-target resume, Space messaging, and canvas-focus flow require manual browser verification
- Two-player synchronization and broader multiplayer browser validation remain deferred
- Destroyed player recovery, configurable or consumable ammunition beyond the X1 action identity, rockets, loot, rewards, and PvP are not implemented
- Live map state is ephemeral, single-node, and has no crash recovery or spatial partitioning
- Initial map, NPC, and combat balance values remain provisional
- No anti-cheat layer

---

## ✅ Immediate Next Task

Manually verify the complete E.2.1/E.2.2 cockpit acceptance flow and the E.2.3
combat-control contract at the supported viewport sizes, including minimap
sizing and reload persistence, responsive docking, click-and-hold steering,
Ctrl/X1 alternating toggles, retained-target resume, Space messaging, and
canvas focus restoration. Multiplayer expansion and broader two-browser
validation remain deferred.


## Experimental SBS / 3D presentation (branch `sbs`)
- [x] Introduce optional Three.js 3D cockpit and binocular side-by-side rendering.
- [x] Preserve the existing 2D game and authoritative movement/combat protocol.
- [x] Implement eye-aware pointer projection and a small unit test suite.
- [ ] Run complete build, precommit, and manual stereo browser verification.
- [ ] Introduce server-authoritative 3D motion and 6DOF flight as a separate milestone.
- [ ] Add optional WebXR and true headset-tracked cockpit controls.

- [x] Revise SBS viewport fit after first Firefox screenshot (instrument sizing
  and peripheral framing, plus pure per-eye fit regression tests).
- [ ] Visually recheck the revised cockpit layout in Firefox and headset.


## Navigation Computer V1 — experimental `sbs` branch

- [x] Full-screen SVG map independent of Classic 2D / 3D / SBS view selection.
- [x] Pointer and coordinate waypoint selection (up to eight legs), undo and clear.
- [x] Authenticated `plot_course` and `stop_navigation` commands.
- [x] Server-side atomic route validation, ordered waypoint progression and manual override.
- [x] Screen accessibility and keyboard controls (M, Escape, focus cycle).
- [x] Regression tests for validation, movement, spoofing and map projection.
- [ ] Run `npm test`, `mix assets.build` and `mix precommit` locally.
- [ ] Manually verify course interaction, browser layout, headsets and two-player sync.
- [ ] Introduce genuine 3D sectors, 6DOF flight and Newtonian/cruise modes.
- [ ] Add real hazard-aware navigation, station docking and a stereo in-world chart.


### Genuine space volume — XYZ first, flight dynamics second

- [x] Server-owned XYZ coordinates with bounded positive/negative altitude.
- [x] Deterministic 3D waypoint movement, proximity and NPC chase range.
- [x] Preserve legacy XY snapshot fields while adding explicit XYZ fields.
- [x] Switch the playable modes to single-view 3D and stereo SBS only.
- [x] Move point-and-click course planning exclusively to the SVG sector atlas.
- [x] Add altitude input, spatial route distance and 3D client interpolation.
- [ ] Run local Elixir, Node and browser regression suites for this migration.
- [ ] Next milestone: manual 6DOF yaw/pitch/roll and world-frame translation.
- [ ] After that: assisted Cruise Flight and Newtonian inertia modes.
- [ ] Later: 3D collision, docking, hazards and server-owned static objects.

- [x] Remove Classic 2D flight renderer and retain overhead mapping only in the atlas.
- [x] Regression-test the two allowed cockpit display modes.
- [ ] Verify refreshed compiled assets and live 3D/SBS switching in Firefox.


### Manual pilot controls slice — SBS branch
- [x] Server-owned signed throttle with forward, neutral, reverse.
- [x] Server-integrated 3-axis attitude and pitch/yaw/roll keyboard commands.
- [x] Assisted Cruise Flight and momentum-preserving Newtonian Flight toggle.
- [x] Bounds-safe tick motion; authenticated Channel controls and telemetry.
- [x] Cabin and SBS flight indicators; keyboard and server tests added.
- [ ] Run `mix precommit` and `npm test` on the laptop and test the flight feel.
- [ ] Improve to quaternion-based attitude and body-frame 6DOF handling.
- [ ] Add throttle controls on screen, smoothing, remapping, docking and inertia tuning.

### Solar System Atlas foundation (2026-11-02)

- [x] SOL system overview is the default main Atlas view; the Sun,
  Mercury through Neptune, and Pluto are all visible/selectable.
- [x] One astronomical catalog with mean AU distances and orbital
  periods; compressed visual orbits and optional inner-system detail.
- [x] Preserve Sector 1-1 as a distinct functional XYZ waypoint chart.
  Clicking an AU marker cannot submit an invalid tactical waypoint.
- [x] No change to currently working flight, weapon, Dart NPC or
  authoritative combat simulation.
- [ ] Server-authoritative star-system and celestial body catalog,
  faction ownership and planetary orbital/region models.
- [ ] Define coordinate transformations and ship's astronomical
  position separately from local per-sector XYZ coordinates.
- [ ] Introduce star-system travel, orbital approach and true
  navigable destinations after the above state model is established.
- [ ] Build EncounterDirector using system region, ship contacts,
  navigation progress and factions; do not tie encounters to a
  fixed NPC respawn coordinate.

### Peaceful login and SOL journey V1 (2026-11-02)

- [x] Remove default Sector 1-1 NPC materialization; no hostile Dart on login.
- [x] Retain Dart NPC definition and its authoritative 3D combat behavior
  behind explicit server-only `start_encounter/1`.
- [x] Production encounters do not automatically respawn after destruction.
- [x] Introduce independent, supervised SOL navigation state per pilot.
- [x] Authenticated planet destination selection, system travel progress,
  arrival, abort and server-owned transit broadcasts.
- [x] Atlas display of SOL region, voyage plan and schematic progress marker.
- [ ] Persist current SOL region across full game server restarts (database).
- [ ] Associate the player's physical ship with orbital region/planet sectors.
- [ ] Implement proper navigation transitions into and out of local flight.
- [ ] Dynamic encounters with NPC-v-NPC skirmishes, contact discovery,
  faction relationships, piracy and neutral traffic.
- [ ] Ephemeris/orbital positions, credible transfer paths, game-time scaling.

### Living universe / first neutral contact (2026-11-03)

- [x] Add an independent Earth–Mars commercial freighter with stable runtime
  identity, scheduled route, reason for travel, manifest and return cargo.
- [x] Advance civilian traffic on the system clock without requiring players.
- [x] Detect nearby vessels using server-side compressed-SOL distance and
  expose contacts to the correct authenticated pilot only.
- [x] Display sensor contacts in the Atlas and allow server-validated
  non-hostile hailing without changing cargo or itinerary.
- [x] Keep pilot navigation, sector combat and tactical NPC spawning separate.
- [ ] Make traffic, missions, cargo and voyage position survive server restarts.
- [ ] Instantiate contacts as shared local tactical encounters with relative
  entry positions, extraction boundaries and reconciliation on exit.
- [ ] Add physical outcomes: trade, rescue, piracy, faction response and
  persistent cargo-delivery consequences.

### Planetary cockpit visualization V1 (2026-11-03)

- [x] Server-authored planetary visual metadata, including true mean
  radii and an explicit visual-only approach/orbit preview stage.
- [x] Three.js camera-relative planet rendering with physically correct
  apparent angular diameter, cloud textures, lighting and atmosphere,
  without widening tactical camera clipping or sector bounds.
- [x] In both standard 3D and SBS, show the actual SOL destination
  growing through cruise and large on arrival (Venus 65° of 70° FOV).
- [x] Keep the planet at a stable world bearing when the ship turns;
  provide a visible cockpit label explaining the preview.
- [x] Add server geometry/navigation and client projection/render tests.
- [ ] Replace visual staging with server-owned, physically meaningful
  planet-centered orbital frames and safe 3D approach spawn positions.
- [ ] Make local ship thrust change its true planet-relative position
  and visible altitude; implement planetary collision/atmosphere rules.
- [ ] Preserve simultaneous multiplayer observers, tactical traffic,
  and clean entry/exit between SOL cruise and local orbital flight.

### Sub-light interplanetary cruise V2 (2026-11-02)

- [x] Explicit `:conventional` vs `:interplanetary_cruise` propulsion states.
- [x] Independent server-owned, compressed system-level ship position
  computed from drive speed and the same one-second multiplayer clock.
- [x] Travel budgets approximately 3–5 minutes inner system, 10 minutes
  Jupiter, 15–22 minutes outer system, without FTL or time compression.
- [x] Disable conventional flight/combat commands during interplanetary cruise.
- [x] Atlas shows current drive, system cruise speed, distance and ETA.
- [x] Cover concurrent players, ticks, position, duration, and command
  isolation in regression tests.
- [ ] Integrate local cockpit movement/velocities into an authoritative
  system-level ship position at sector boundaries.
- [ ] Generate safe semi-random planetary approach positions and real
  celestial bodies in their local sector centers.
- [ ] Preserve the actual midcourse position when abandoning cruise instead
  of restoring the departure region.
- [ ] Implement drive acceleration/deceleration and possible interception.


### Planetary orbital regions V2 (2026-11-03)

- [x] Nine independently supervised SOL planetary tactical regions,
  including Earth, plus an isolated legacy `1-1` combat test fixture;
  server-owned map identities and join validation.
- [x] Arrival side derived from the incoming SOL voyage, with deterministic
  pilot staggering and heading toward the actual planet centre.
- [x] Separate local provisional-kilometre coordinates from compressed
  system-wide cruise coordinates, preserving one shared map per planet.
- [x] Automatically transfer the pilot's Phoenix channel on arrival,
  update the local Atlas bounds and keep SOL navigation broadcasts global.
- [x] Real planetary mean radii, camera-relative planet rendering and
  a server-controlled exclusion sphere, now lethal when crossed.
- [x] Remove the four original procedural test asteroid spheres and
  relocate the starfield around the camera in large maps.
- [x] Add directional arrival, region routing, collision and view tests.
- [x] Send live Earth pilots to `sol:earth` with a real-radius map,
  retaining the old `1-1` first-login spawn only under test configuration.
- [ ] Preserve active hull/shields/loadout and physical orbital coordinates
  across region transitions, disconnects and full server restarts.
- [ ] Implement trajectory-preserving interplanetary handoff, orbital
  velocity/gravity, planet rotation, real docking and atmospheric entry.
- [ ] Add permanent stations, asteroid fields and contextual traffic
  in the respective planetary regions.


### Fatal planetary impact V1 (2026-11-03)

- [x] Replace the old harmless orbital-volume clamp with a server-owned
  lethal impact boundary at 1.08× the planet's actual mean radius.
- [x] Use swept 3D segment-sphere intersection to prevent high-speed
  tunnelling during manual flight or local plotted autopilot.
- [x] Zero hull, shields and momentum; mark destroyed and clear targets,
  waypoints and NPC pursuit; broadcast a single planetary-death event.
- [x] Show a planet-named crash message and release pointer lock on death.
- [x] Add pure and live map integration tests for normal approach,
  first impact, fast through-crossing and safety of other flight modes.
- [ ] Add escalating proximity/collision alerts and gravitational effects.
- [ ] Implement controlled respawn or rescue/recovery workflow for pilots.
- [x] Enable identical lethal collision and proximity warning behavior
  for Earth and every other SOL planetary region.


### Planetary proximity warning V1 (2026-11-03)

- [x] Server-owned CAUTION (1.55× lethal radius) and CRITICAL
  (1.20× lethal radius) proximity bands for all nine orbital maps.
- [x] Publish one event per zone change, including retreat to safety,
  without emitting a warning every 100ms simulation tick.
- [x] Include current per-pilot 3D collision clearance and warning level
  in world snapshots for late join/reconnect recovery.
- [x] Add amber/red cockpit alerts and corresponding stereoscopic in-world
  HUD warnings; hide the flat warning in SBS.
- [x] Test thresholds, 3D altitude, transition suppression,
  in-range join snapshots and complete caution→critical→clear flight.
- [ ] Add optional configurable warning audio.
- [ ] Add recovery/respawn mechanics, planetary approach autopilot
  protections and realistic atmospheric/orbital physics.

### Planet hazard parity across SOL and future catalogue extension (2026-11-03)

- [x] One physical radius source in the authoritative SOL catalogue.
- [x] All nine navigable worlds, **including Earth**, receive the same
  region-local kilometres, approach-direction arrival, caution/critical
  alerts, lethal swept collision and destroyed-ship protocol.
- [x] First Earth gameplay session enters `sol:earth`; the original
  `1-1` sector is retained only as an explicit test-only fixture.
- [x] Planetary region sizing can expand automatically for very large
  future planets; no special collision handler per body.
- [x] Generic future planet-ID syntax and procedural texture fallback.
- [x] Add full nine-planet map-server integration crash parity test plus
  fresh-Earth safe-arrival and catalogue radius regression tests.
- [ ] Build multi-system celestial catalogue and separate cross-system
  travel/wormhole transitions (future phase, not part of this release).
- [ ] Add destruction recovery and persistent ship state between sessions.


### Living SOL close-pass encounter V1 (2026-11-03)

- [x] Six independent, scheduled traffic vessels with distinct routes,
  purposes, manifests and return journeys, simulated without players.
- [x] Encounter opportunities derive from **real** intersecting SOL routes,
  relative velocity, departure time and fixed close-approach radius.
- [x] Announce a close pass once per pilot per vessel voyage, isolate pilot
  events over Phoenix and include current flyby in reconnection snapshots.
- [x] Show a 3D traffic ship in normal/SBS cockpits using real SOL relative
  bearing and distance-dependent visual magnification.
- [x] Provide Hail and Dismiss; private manifest requires server-checked
  authenticated hailing. Do not spawn NPCs or expose cargo on passive scans.
- [x] Extend traffic, navigation, event privacy, and cockpit geometry tests.
- [ ] Design a persistent **shared tactical encounter instance** at true
  relative vessel coordinates, with voluntary intercept/approach and rejoin
  to original sublight trajectory.
- [ ] Add lawful/hostile dispositions, distress requests, NPC-v-NPC
  conflicts, escorts, weapons and consequence/reputation systems.
- [ ] Persist traffic schedules and pilot encounter state across restarts.
 
### EncounterDirector V1 — server-owned classification (2026-11-03)

- [x] Classify already-observed strategic contacts as neutral flyby,
  patrol attention or hostile contact, with no NPC spawning.
- [x] Bind faction-owned Venus patrol to ZOC and provisional server-only
  standing threshold; leave missing standing neutral.
- [x] Emit pilot-specific classified encounter snapshots/events without
  stopping cruise; label classifications in the normal cockpit panel.
- [x] Add unit and navigation event regressions for classification.
- [ ] Integrate durable player-faction reputation and lawful NPC disposition
  changes; default traffic remains non-hostile.
- [ ] Add shared tactical encounter instances, voluntary/forced interception
  and route-safe resumption; policy labels do not start combat.
- [ ] Run Mix/JS suites and manually verify 3D + SBS UI in a live browser.


### Encounter decision hold V1 (2026-11-03)

- [x] Freeze only the involved pilot's strategic cruise progression upon
  a real server-owned close pass; all other ships and traffic keep moving.
- [x] Retain a pilot-scoped pending decision across channel reconnects.
- [x] Reject spoofed encounter identities, unsupported choices, premature
  course aborts and repeated resolutions.
- [x] Show a modal with Hail and Ignore / Resume actions, including an
  SBS per-eye version, while retaining real sensor-range validation.
- [x] Add deterministic navigation and authenticated-channel regressions.
- [ ] Execute Mix/asset suites, build assets, and visually verify normal 3D
  and SBS flows in a real browser/HMD.
- [ ] Introduce physical voluntary/forced interception, shared tactical
  instancing and ship-state-safe resumption, including NPC motion policies.
- [ ] Persist paused voyages and NPC traffic across full server restarts.

### SBS development LAN listener (2026-11-03)

- [x] Bind Phoenix dev endpoint to `0.0.0.0:4000` by default to support a
  headset/phone connecting to the laptop over trusted LAN Wi-Fi.
- [x] Provide `DARKORBIT_LOOPBACK_ONLY=1` opt-out for laptop-only debugging.
- [ ] Verify remote HMD pairing from another device and review production
  origin/security rules before any public hosting.


### Encounter popup reliability and paired HMD notification (2026-11-03)

- [x] Open the existing laptop encounter modal as soon as the authenticated
  first-contact event arrives, without waiting for a navigation snapshot.
- [x] Restore held decision state from navigation snapshots on reconnect;
  block underlying Atlas focus until decision is resolved.
- [x] Mirror read-only, authenticated close-pass status to the paired
  headset in both SBS eyes while the helmet is in cockpit mode.
- [x] Add unit tests for per-eye rendering and channel tests for
  privacy filtering and read-only commands.
- [ ] Run tests, build assets, and manually verify both displays.
- [ ] Add authorized VR controls for choices only if/when the helmet is
  upgraded from a read-only viewer to an authenticated input device.

### Reliable procedural SOL encounter traffic (2026-11-03)

- [x] Retain the six existing scheduled traffic ships.
- [x] Launch a real, shared, server-owned vessel along a converging lane for
  the current playtest's interplanetary voyages; randomize type and phase.
- [x] Prevent population growth beyond 32 added vessels; expire each after
  15 minutes while retaining scheduled ships.
- [x] Preserve a pending pilot's established hail connection after physical
  sensor separation, without permitting arbitrary remote hails.
- [x] Add regression tests for a fresh corridor with no existing fleet,
  bounded spawning, contact selection and travel resumption.
- [ ] Execute tests and verify Earth–Venus popup on laptop/paired headset.
- [ ] Tune actual encounter chance, route density, sector/faction hostility,
  and implement shared tactical combat interception.



### SOL tactical encounter handoff (2026-11-03)

- [x] Allow Engage for held hostile and patrol contacts only; retain Hail
  and Ignore/Resume for ordinary neutral flybys.
- [x] Validate encounter ID and session on server before entering combat;
  prevent forged entry and resuming a voyage during an active fight.
- [x] Spawn a Dart-class NPC under contact's callsign in the pilot's current
  authoritative orbital map, near the live ship and outside planetary
  exclusion geometry. Use current planet visuals for collision clarity.
- [x] Permit local cockpit movement and weapon use during tactical hold,
  while retaining SOL voyage position/progress and multiplayer isolation.
- [x] Server-check NPC destruction before victory; permit explicit retreat,
  clean up enemy and target locks, resume original travel.
- [x] Route paired read-only HMD world subscriptions to actual orbital map.
- [x] Add core and Phoenix channel regression tests including auth and
  rejected client-originated victory.
- [ ] Execute full Mix/JS suites and verify laptop plus headset gameplay.
- [ ] Build a true isolated mid-voyage tactical arena rather than temporarily
  using the pilot's current planetary combat map.
- [ ] Implement pilot defeat/respawn, battle rewards, independent ship models,
  trade scene choices, and faction-specific patrol interception.

- [x] Cancel a defeated pilot's held SOL course on authoritative destruction
  and prevent a dead pilot from invoking a fake defeat or retreat.
- [x] Render tactical Dart variants as the actual 3D Dart ship model.
- [ ] Implement final death/respawn UX and economic consequences.


### Neutral trader attack choice (2026-11-03)

- [x] Offer Attack vessel for neutral SOL close-pass contacts, in addition
  to Hail and Ignore / Resume.
- [x] Validate the exact server-owned neutral encounter and pilot session
  before entering a local 3D tactical fight.
- [x] Make neutral tactical opponents passive until a confirmed damage hit;
  retain proactive hostile raider behavior.
- [x] Add UI action-choice tests and headless tests for retaliation, close
  pass, authorization, and voyage resumption.
- [ ] Run Mix/JavaScript suites and verify laptop plus SBS headset.
- [ ] Implement actual trader ship visuals and AI/behavior beyond the
  existing Dart-class tactical placeholder.
- [ ] Add standing/reputation penalties, faction-law response, cargo/loot,
  and rewards for attacking civilian traffic.


### Scow merchant hull implementation (2026-11-03)

- [x] Register a separate Scow NPC type with reference-grounded 210 armor
  and Garnet 10-class laser and provisional balance values.
- [x] Assign server-owned Scow identity to independent traders, couriers
  and scheduled merchant traffic without changing their routes or cargo.
- [x] Spawn actual Scow combat opponents via authenticated neutral SOL
  encounter handoff, while hostile fighters retain the Dart placeholder.
- [x] Create and render an original blue low-poly cargo vessel in normal
  cockpit and SBS phone headset with existing target selection geometry.
- [x] Add model and simulation tests for class identifiers, hull, damage
  and SOL encounter mapping.
- [ ] Verify full Mix/JavaScript test suites and live laptop/HMD gameplay.
- [ ] Implement NPC captain doctrine: flight, surrender, radio threats,
  variable morale and faction standing/reputation penalties, rather
  than assuming every attacked Scow fights to destruction.
- [ ] Implement larger Tanker merchants as a separate hull with stronger
  defenses; add salvage and transferred cargo after surrender/defeat.


### Scow graphics verification and impact orientation (2026-11-03)

- [x] Replace generic gray SOL close-pass preview with actual Scow
  merchant mesh (Dart for fighter contacts) using shared model factory.
- [x] Preserve Scow preview from `pending_encounter` during pilot hold.
- [x] Publish an authoritative `ship_class` in tactical map NPC snapshots;
  render identical class in laptop and paired SBS phone.
- [x] Display selected NPC class in the cockpit target readout.
- [x] Add model-switch, pending-contact and ship-class regression tests.
- [ ] Run full JS/Elixir test suite and check actual headset graphics.
- [ ] Track authoritative NPC heading and calculate front/aft impact arc
  from server-side 3D weapon hit geometry, not browser-derived positions.
- [ ] Replace pooled shields with forward/aft shields and original
  class-based mitigation, including Scow Aft-1.
- [ ] Add component damage (engines, beam, missiles, shields, ECM),
  persistent system status, handling penalties and TAC presentation.
- [ ] Separate cosmetic model hit markers from server-owned damage outcomes.


### Merchant voyage-aligned tactical movement (2026-11-03)

- [x] Stop using the four-corner legacy NPC patrol for merchant encounters.
- [x] Carry the existing shared SOL origin/destination through the
  authenticated encounter into the tactical map.
- [x] Project a short straight merchant transit lane using its real
  strategic bearing, deflecting only to avoid planet impacts/map edges.
- [x] Keep neutral Scow flight moving while defensive turret fire uses
  server-confirmed damage; do not make it chase the attacking pilot.
- [x] Publish stable course heading to desktop and headset renderers.
- [x] End combat on Scow lane exit, remove the local NPC, clear target locks,
  and resume the owner's SOL voyage even after losing the client connection.
- [x] Add pure route geometry and AI tests plus world-level escape tests.
- [ ] Run Mix and asset tests, then verify moving Scow in laptop and headset.
- [ ] Move combat to a genuine mid-space battle bubble tied continuously
  to shared strategic ships; reconcile ship death, cargo, and encounters.
- [ ] Add merchant captains' flee, surrender, defend, and radio responses,
  informed by morale, player threat and ship damage.


### Sunracer, inventory/equipment, and Scow survival (2026-11-03)

- [x] Make default ship 1 the original Sunracer while keeping existing
  player ownership, two configurations and other purchasable hulls.
- [x] Set starter Garnet to 10 and base armor to 300; four-tonne cargo
  capacity, Forward-1 shield, missile tube, .20G, and 45°/s as metadata.
- [x] Add Beryl/Sapphire replacement laser rules for Sunracer hardpoint;
  preserve additive multi-laser loadouts for later ship classes.
- [x] Expose authenticated server-owned equipment inventory and C-1/C-2
  layout at /equipment, with atomic fitting and account-scoped activation.
- [x] Create persistent server-owned commodity stacks and enforce ship
  cargo capacity under account and inventory locks.
- [x] Make provoked Scows evade at <=80% hull and surrender at <=35%;
  owner can accept surrender with server verification and return to SOL.
- [x] Protect surrendered merchants against automatic or manual laser hits.
- [x] Add Core, Darkorbit DB and Phoenix controller/channel regression tests.
- [ ] Run full test/build suites and verify browser/SBS headset gameplay.
- [ ] Replace provisional speed with original Sunracer acceleration and
  turn dynamics as appropriate to game's tactical speed scale.
- [ ] Add original forward/aft directional shield-class laser and collision
  reduction, subsystem damage, equipment status and repair.
- [ ] Add an actual merchant captain's varied morale, danger appraisal,
  surrender offers and reputation/behavior consequences.
- [ ] Build docking/shipyard purchase, commodity trading and capacity-safe
  cargo transfer from a surrendered/destroyed strategic vessel.
- [ ] Reconcile persistent strategic NPC identity with temporary tactical
  encounter actor before implementing real cargo theft/loot.
