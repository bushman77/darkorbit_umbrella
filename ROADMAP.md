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
