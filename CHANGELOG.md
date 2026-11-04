# Changelog

## Unreleased

### Milestone A — Persistent player domains

- Added account registration, authentication, inventory, fleet, two ship loadouts, preferences, titles, and starter-state provisioning.
- Added catalog-aware equipment and ship ownership operations.

### Milestone B — Persistent-state hardening

- Made registration and equipment replacement atomic, ownership scoped, and constraint backed.
- Added row locking and concurrent mutation tests to prevent inventory and loadout duplication.

### Milestone C — Ship stats and authoritative world

- Added configurable ship/equipment catalogs and pure derived ship statistics.
- Added the supervised `1-1` map, in-memory player sessions, server-owned bounded movement, deterministic ticks, and transport-neutral world events.

### Milestone D — Authenticated browser flight

- Added credential login, short-lived signed socket authentication, and the authenticated world channel.
- Added the Canvas 2D sector client, original placeholder art, HUD telemetry, authoritative interpolation, movement synchronization, and disconnect cleanup.
- Added `demo_pilot` and `wing_pilot` development accounts for browser testing.

### Milestone D.1 — Continuous mouse navigation

#### Added

- Added classic click-and-hold canvas navigation: the ship continuously retargets toward the held pointer at a throttled cadence, including while the camera moves beneath a stationary cursor.
- Added pointer-capture lifecycle handling for release, cancellation, lost capture, window blur, and document visibility changes.
- Added focused JavaScript tests for click navigation, throttling, camera-aware retargeting, redundant-command suppression, the near-ship dead zone, and cancellation safety.

#### Preserved

- Movement remains server-authoritative: the browser sends destinations only, while the world simulation continues to validate map boundaries and own ship positions and speeds.

#### Verification

- Graphical ship flight and continuous mouse navigation were manually verified.
- Two-player synchronization is covered by automated channel tests and awaits manual verification in two browser sessions.

### Milestone E — Server-authoritative NPC combat

#### Added

- Added the configurable original `Rift Skirmisher` NPC definition with deterministic sector `1-1` spawns and provisional combat, movement, patrol, and respawn values.
- Added pure deterministic combat mechanics for legal targets, range, tick-based cooldowns, non-negative damage, shield absorption, hull damage, and destruction.
- Added pure `idle`, `patrol`, `pursue`, `attack`, and `destroyed` NPC decisions with deterministic local patrol routes.
- Extended the map process with world-owned NPC state, AI ticks, player and NPC health, selected targets, laser attacks, NPC removal, and tick-based respawning.
- Added authenticated `select_target`, `clear_target`, and `laser_attack` channel intentions plus authoritative targeting, NPC-state, damage, destruction, and spawn events.
- Added a catalog-defined Phoenix pulse emitter so existing pilots have combat damage without login-time inventory mutation.
- Added right-click and nearest-hostile targeting, target hull/shield telemetry, a Space/click fire control, NPC labels and indicators, animated beams, shield/hull impacts, explosions, and server-driven HUD health.
- Added focused Core, world, channel, concurrency, disconnect, and JavaScript targeting/combat tests while preserving the navigation suite.

#### Verification

- `mix compile --warnings-as-errors`, `mix test`, `mix precommit`, `mix assets.build`, the JavaScript test command, and `git diff --check` pass.
- The Elixir suite has 78 passing tests with no failures: 32 Core, 30 persistence, and 16 web/channel tests.
- The JavaScript suite has 16 passing tests with no failures, including all Milestone D.1 pointer-navigation regressions.

#### Limitations

- The complete browser combat encounter and two-browser observation flow have not yet been manually verified.
- Destroyed players do not respawn; ammunition, rewards, loot, PvP, spatial partitioning, multi-node ownership, and live-state recovery remain out of scope.
- Initial NPC and weapon values are provisional balancing data.

### Milestone E.1 — Classic combat controls, persistent target lock, and action hotbar

#### Added

- Added authoritative `engaged_target_id` state alongside selected `target_id`, plus explicit combat engage, disengage, and structured hotbar-action commands.
- Added a server-defined ten-slot action catalog. Slot 1 contains the existing Phoenix pulse emitter; slots 2 through 0 are safe empty placeholders and do not mutate inventory or ammunition.
- Added map-tick automatic player attacks with server-owned range, damage, cooldown, destruction, and validity enforcement. Out-of-range engagement pauses without moving the player and resumes when range becomes valid.
- Added idempotent repeated engagement, automatic target/engagement clearing on invalidation and destruction, preserved movement destinations during combat, and clean respawn/disconnect lifecycle handling.
- Added left-click rendered-NPC hit testing before navigation capture while preserving empty-space single-click and click-and-hold movement. Existing right-click targeting remains available.
- Added replicated combat-facing state and smooth shortest-path ship rotation toward moving engaged targets, independent from navigation direction.
- Added a responsive bottom-center hotbar with number-row and click activation, Space engagement, Esc cancellation, and distinct selected, active, empty, and authoritative-cooldown visuals.
- Added keyboard guards for repeated keys, modifier chords, form controls, buttons, and content-editable fields.

#### Tests

- Added Core coverage for the action catalog, distinct selection/engagement, tick-owned automatic fire, cooldown enforcement, range pause/resume, concurrent movement, cancellation, invalid/repeated actions, automatic destruction, player destruction, disconnect cleanup, and respawn lock clearing.
- Added channel coverage for hotbar definitions, explicit engagement/action commands, empty/invalid slots, repeated engagement, cancellation, and multiplayer state synchronization.
- Added JavaScript coverage for left-click target interception without movement, render-dimension hit testing, slots 1 through 0, input/key-repeat guards, combat-facing precedence, moving targets, navigation-facing restoration, and wrap-safe rotation smoothing.

#### Verification

- `mix compile --warnings-as-errors`, `mix precommit`, `mix assets.build`, and `git diff --check` pass.
- `mix test` passes with 84 tests: 37 Core, 30 persistence, and 17 web/channel tests.
- The JavaScript suite passes 21 tests across 16 top-level cases, including all prior pointer-navigation regressions.
- Manual browser verification confirmed navigation, NPC targeting, persistent laser engagement, combat facing, and circular combat maneuvering.
- Broader two-browser observation remains deferred.

#### Limitations

- Slots 2 through 0 intentionally have no assigned action. Ammunition, rockets, abilities, consumables, and equipment assignment remain future work.
- Destroyed player recovery, rewards, loot, PvP, and persistent/multi-node live world state remain out of scope.

### Milestone E.2.1 — Modular cockpit HUD, movable windows, and persistent layouts

#### Added

- Added a reusable cockpit window manager with unique window IDs, desktop defaults, title-bar-only Pointer Event dragging, pointer capture, focus ordering, viewport clamping, lock/unlock mode, collapse/expand, hide/restore, reset, and keyboard arrow positioning.
- Added versioned, failure-safe local layout persistence namespaced by the non-sensitive numeric player ID. Position, visibility, collapsed state, and HUD lock state survive refreshes; incompatible or malformed data safely falls back to current defaults.
- Converted ship telemetry and authoritative target/combat telemetry into standardized cyan/blue and hostile orange cockpit windows while preserving every existing combat action and health indicator.
- Replaced the minimap painted into the main space canvas with one dedicated, resize-aware, throttled minimap canvas that consumes the same interpolated entity collection and authoritative map boundaries.
- Added a compact cockpit settings surface, window visibility menu, narrow-screen horizontal dock, reduced-motion behavior, and pointer boundaries that prevent cockpit interactions from reaching the navigation canvas.
- Kept the ten-slot action hotbar anchored at bottom center and outside the window manager, preserving number-row, Space, Esc, click, empty-slot, and authoritative cooldown behavior.

#### Tests

- Added JavaScript coverage for unlocked and locked dragging, title-bar capture cleanup, collapse/expand, hide/restore, defaults reset, persistence/restoration, corrupted or unavailable storage, viewport clamping, resize docking, canvas input isolation, keyboard movement, hotbar-key preservation, reduced motion, minimap projection, render throttling, and lifecycle cleanup.
- Extended the authenticated game-page test to verify the per-player layout namespace, exactly three cockpit windows, one minimap canvas, the HUD controls, and the unchanged hotbar surface.

#### Verification

- `mix compile --warnings-as-errors`, `mix test`, `mix precommit`, `mix assets.build`, and `git diff --check` pass.
- `mix test` passes with 84 tests: 37 Core, 30 persistence, and 17 web/channel tests.
- `npm test` passes 38 JavaScript tests across 29 top-level cases, including all existing navigation and combat regressions.
- Manual browser verification of the E.2.1 cockpit has not been performed. The complete layout-editing, persistence, resize, navigation, and combat acceptance flow remains required before graphical sign-off.

#### Limitations

- At the E.2.1 milestone boundary the minimap was display-only; Milestone E.2.2 supersedes that limitation with server-authoritative minimap navigation.
- Layouts are local to one browser profile and are not synchronized through the account database.
- Broader multiplayer validation, multiplayer expansion, recovery, rewards, ammunition, loot, PvP, and persistent or multi-node live world state remain deferred.

### Milestone E.2.2 — Interactive and scalable minimap

#### Added

- Added locked-HUD minimap click and click-and-hold steering through the existing pointer-navigation lifecycle. Minimap gestures project into authoritative map boundaries and submit destination intentions without changing local entity positions, combat state, or server-owned movement rules.
- Added visible minus and plus controls to the minimap header. Each activation changes the floating minimap width by 40 pixels, bounded from 192 to 520 pixels and clamped to the available viewport.
- Persisted the minimap width in the existing version-1, per-player cockpit layout payload. Layouts saved before the width field existed retain all coordinates, visibility, collapse, and lock state while adopting the 272-pixel default.
- Kept size controls interactive while the HUD is locked. The compact horizontal dock continues to own narrow-screen panel sizing while retaining the selected floating width for supported viewports.

#### Tests

- Added JavaScript regression coverage for locked sizing controls, exact 40-pixel steps, rendered width application, automatic persistence and reload restoration, legacy payload compatibility, reset persistence, configured bounds, viewport bounds, and compact-dock behavior.
- Preserved and reran the existing JavaScript navigation and combat regressions, including continuous minimap steering, projection after CSS resize, active-combat isolation, cancellation cleanup, and server-authoritative destination submission.
- Extended the authenticated game-page test to require exactly one visible decrease control and one visible increase control.

#### Verification

- `mix precommit` passes with 84 Elixir tests: 37 Core, 30 persistence, and 17 web/channel tests.
- `npm test` passes 46 JavaScript tests across 37 top-level cases.
- The focused authenticated game-page test passes 3 tests, `mix assets.build` passes, and `git diff --check` passes.
- Manual browser verification was not performed. Minimap sizing, persistence across reload, locked-HUD controls, responsive docking, and click-and-hold steering still require graphical acceptance at the supported viewport sizes.

#### Limitations

- Layout size remains local to one browser profile and is not synchronized through the account database.
- On compact viewports the horizontal dock intentionally overrides the floating minimap width; the persisted width is used again when the cockpit returns to floating mode.

### Milestone E.2.3 — Server-authoritative laser toggle controls

#### Added

- Replaced ambiguous engagement shortcuts with one atomic `Core.World`/map/channel laser toggle shared by Ctrl and the slot-1 action. Toggle-off preserves the selected target and clears only active engagement; Escape retains explicit clear-and-disengage behavior.
- Reworked the server action catalog around explicit action ID, type, and activation mode. Slot 1 now contains toggle-mode X1 ammunition linked to, but distinct from, the existing Phoenix pulse-emitter weapon; no inventory item, rocket, or consumable was added.
- Preserved the pulse emitter's server-owned damage, range, and cooldown state across toggles, preventing stop/resume from accelerating its firing cadence.
- Added correct `ControlLeft`/`ControlRight` handling, repeat and Ctrl-chord rejection, reserved-Space unavailable messaging, metadata-driven hotbar active state, and authoritative `AUTOFIRE`/`STANDBY` presentation.
- Kept NPC selection independent from activation, retained destruction and clear lifecycles, and restored gameplay focus when the main canvas is clicked without consuming native cockpit-button or editable-field keyboard behavior.

#### Tests

- Added Core regressions for direct, slot, and alternating toggles; selection-preserving stop/resume; explicit clear; sequential NPC destruction/selection; cooldown preservation; and invalid, empty, unauthorized, destroyed-player, and missing-target handling.
- Extended channel coverage for X1 action metadata, shared toggle state, ignored spoofed toggle fields, multiplayer engagement/disengagement broadcasts, retained selection, and fresh activation.
- Added JavaScript coverage for both physical Ctrl keys, `event.ctrlKey`, held-key suppression, modifier chords, reserved Space behavior, and metadata-driven active indicators while retaining every existing cockpit, minimap, navigation, targeting, and rotation regression.

#### Verification

- `mix precommit` passes 87 Elixir tests: 40 Core, 30 persistence, and 17 web/channel tests.
- `npm test` passes 48 JavaScript tests across 39 top-level cases.
- `mix assets.build` and `git diff --check` pass.
- Manual browser verification was not performed. Ctrl/X1 alternation, retained-target stop/resume, Space messaging, canvas focus restoration, minimap preservation, and two-browser synchronization remain pending.

#### Limitations

- Slots 2 through 0 remain empty. Space reserves a future single-shot rocket but does not create a rocket attack.
- X1 is currently a non-inventory action identity; configurable ammunition selection, quantities, consumption, X2/X3/X4, rockets, and other hotbar assignments remain future work.


## 2026-11-01 — Experimental SBS branch
- Added optional 3D cockpit and stereoscopic dual-eye renderer with Three.js.
- Kept the original Canvas 2D mode and existing Phoenix combat/navigation contracts.
- Added render-only world coordinate and per-eye pointer projection utilities/tests.
- Added a display selector, keyboard fallback, setup dependency and design notes.
- Build and real browser/headset verification pending; server is still XY only.


### SBS cockpit visibility follow-up
- Shrunk/repositioned 3D cockpit readouts and made eye-aspect fitting adaptive.
- Thinned and repositioned canopy beams toward peripheral eye views.
- Hid the desktop controls hint in stereo mode; added viewport-fit tests.
- First in-browser SBS rendering observed in user screenshot, but revised
  geometry and headset compatibility still require manual verification.


### 2026-11-01 — Navigation Computer V1 (`sbs`)
- Added an SVG sector overview with coordinate input, eight-point course drafts,
  route preview, and server-reported helm/position telemetry.
- Implemented `plot_course` with full server-side validation and deterministic
  ordered waypoint progression, plus session-bound `stop_navigation`.
- Manual `move` cancels autopilot; destruction also clears a course.
- Preserved Classic 2D, single-view Three.js, and dual-eye SBS render modes.
- Added Core, channel, and pure JavaScript tests. Static JS checks and partial
  geometry checks passed; full automated suites and manual browser verification
  remain outstanding.


### SBS branch — XYZ world and sector atlas transition (2026-11-01)
- Made XYZ authoritative on the server with bounded altitude and full 3D
  Euclidean navigation and combat range.
- Added backwards-compatible `position_3d`, `destination_3d`, `route_waypoints_3d`
  and sector `volume` fields to the wire snapshots.
- Retired Classic 2D from the gameplay view selector: Three.js single-view
  and true dual-eye SBS are the only presented cockpit views.
- Recast the top-down SVG chart as the sector atlas with Z altitude selection
  and real XYZ route distances; legacy minimap is telemetry-only.
- Added spatial visualization, height interpolation and regression tests.
- Full suite, asset compilation and in-browser verification remain pending.

### SBS branch — remove legacy 2D flight fallback (2026-11-01)

- Removed the legacy 2D ship/grid/stars rendering pipeline from `client.js`.
- Replaced its Canvas 2D input canvas with a transparent DOM pointer target.
- Restricted `V` and the selector to 3D/SBS; added display-mode tests.
- Missing WebGL now reports an error rather than activating an obsolete view.
- The flat navigation atlas and 3D cockpit CanvasTexture readouts remain.


### SBS branch — Manual Cruise/Newtonian flight (2026-11-01)
- Added `Core.World.FlightDynamics`: server-owned signed thrust, velocity,
  attitude, sector bounds and two flight physics modes.
- Added authenticated `flight_controls` commands and 3D/SBS keyboard piloting.
- Flight keys follow the original Space Rogue layout with a modern reverse
  throttle extension; `Ctrl+E` toggles flight physics.
- Added HUD readouts and Core/Channel/browser regressions.
- Browser flight-control tests passed in isolation; run full local suites and
  evaluate flight handling in Firefox before treating it as production ready.

### SBS branch — corrected flight axes and throttle (2026-11-01)

- Reassigned W/S to forward/reverse throttle ramp while held.
- Mapped arrows to pitch, A/D to yaw, Z/C to roll, and F to release steering.
- Corrected 3D camera orientation using an explicit forward vector and
  roll-adjusted camera up vector, matching server-positive yaw/pitch.
- Added live heading, pitch, roll indicators and deterministic input/basis tests.
- Atlas input release is now silent, avoiding cancellation of an active route.

### SBS branch — finalized player flight keymap (2026-11-01)

- W/S pitch up/down; A/D yaw left/right; Q/E roll left/right.
- = accelerates and - decelerates signed throttle, including reverse.
- Throttle keys are hold-to-ramp in normalized 10% steps every 120 ms,
  independent of OS key repeat; numeric keypad +/- are supported.
- Preserved Ctrl+E for Cruise/Newtonian switching and F to release steering.
- Updated UI instructions and automated mapping/modifier tests.

### SBS branch — pitch-down responsiveness fix (2026-11-01)

- S can pitch continuously down through vertical, no +/-89-degree cutoff.
- Most recently pressed pitch key takes precedence during W/S overlap.
- Flight HUD shows whether UP/DOWN pitch input is currently registered.
- Regression tests cover key reversal, +/- pitch symmetry and inverted camera basis.

### SBS branch — make web asset rebuild reliable from umbrella root (2026-11-01)

- Added root-level Mix `assets.setup`, `assets.build`, and
  `assets.deploy` aliases that explicitly execute the web child's aliases.
- Prevents repeated testing of outdated cockpit JavaScript after source pulls.
- Documented checking the built `app.js` for the latest `lastPitchKey` code
  before diagnosing the W/S and obsolete X key mapping.

### SBS branch — smooth, capped pitch/yaw/roll (2026-11-01)

- Added server-owned angular velocity, per-axis turn acceleration/braking
  and capped angular rates, with smooth opposite-key reversals.
- Changed pitch/yaw/roll integration to trapezoidal angular displacement.
- Added shortest-path wrapped-angle rendering interpolation for 3D and SBS.
- Added turn-rate telemetry on cockpit and stereoscopic HUD.
- Added browser interpolation tests, server angular-dynamics tests and
  socket telemetry assertion; full Mix suite must run on the laptop.

### SBS branch — thrust follows current nose (2026-11-01)

- Corrected Cruise Flight to integrate a signed forward-speed scalar and
  project world-space velocity along the ship's live heading every tick,
  removing unintended prior-course drift after turning.
- Newtonian thrust continues to use the live nose while retaining
  momentum; switching to Cruise converts forward momentum and removes
  sideways drift.
- Added regression tests for turn-before-thrust, turn-while-moving,
  pitched climbs, negative throttle, and Cruise/Newtonian transitions.
- Reset cruise speed on legacy movement, atlas route and navigation stop.

### SBS branch — Space Rogue manual red laser firing (2026-11-01)

- Added Space hold-to-fire, server-authoritative nose-aimed 3D raycasts
  against living NPCs, including misses consuming real weapon cooldown.
- Separate red manual laser beams with glowing streaks in 3D and SBS;
  damage and beam endpoints are replicated by authoritative events.
- Left existing Ctrl/slot-1 automatic fire intact; added L as an original-
  style shortcut for automatic X1 fire and T for nearest-hostile targeting.
- Added ray collision, no-lock fire, session anti-spoofing, cooldown and
  keyboard regressions. R weapon cycling remains deferred.

### SBS branch — simplify combat interface and protect Space input (2026-11-01)

- Removed large right-hand target information panel and its toggle button,
  while preserving 3D/SBS target display and minimal hit/miss messages.
- Removed panel from saved-layout definitions and visibility menu.
- Captures Space keydown/keyup to stop button focus from consuming the
  laser trigger or inadvertently toggling autofire.
- Added layout persistence and keyboard-focus regression tests.

### SBS branch — body-relative quaternion orientation (2026-11-01)

- Replaced fixed-world Euler attitude for simulation and aiming with a
  normalized body-relative quaternion, retaining old Euler telemetry.
- Updated cruise and Newtonian thrust, manual laser ray, 3D/SBS camera
  and other player meshes to share authoritative orientation.
- Added shortest-path quaternion slerp and actual nose-based HUD heading,
  pitch and bank readouts plus body-relative regression coverage.

### SBS branch — dual wing-mounted laser hits (2026-11-01)

- Replaced single visual-offset shot with two server-positioned,
  body-relative laser rays from symmetric cockpit/wing emitters.
- Traced independent ray/target intersections using authoritative
  orientation, 3D NPC collision spheres, and the existing weapon range.
- Combined concurrent hits in one authorized burst and single cooldown;
  damage is not doubled if both rays connect with the same target.
- Broadcast per-wing endpoints, collision flags and impacted NPC states;
  client applies all damage states and draws two red beams and hit flashes.
- Aligned NPC render positions with collision geometry and included
  twin wing beams on existing targeted automatic fire.
- Added paired-hit, miss, yaw/roll, multi-target and world damage tests.

### SBS branch — 5× pulse emitter range and explicit laser hits (2026-11-01)

- Increased server-enforced player pulse laser range from 720 to 3,600 units
  for wing-mounted manual fire and automatic X1 engagements.
- Added 3,200-unit positive hit/actual NPC damage regression and out-of-range
  negative tests while preserving existing cooldown and total damage.
- Added HIT N/2 and MISS confirmation with server-reported shield/hull damage
  in mono and stereo cockpits; reticle changes color for 1.6 seconds.
- Added selected-target range in world units with IN RANGE/OUT OF RANGE and
  shield/hull readings directly on the stereoscopic cockpit HUD.
- Extended dual red beam rendering to 550ms, increased thickness and impact
  flash visibility; existing server-owned beam/impact geometry is unchanged.

### Sector 1-1 demo — one original-inspired Dart fighter (2026-11-02)

- Replaced the three `rift_skirmisher` demo spawns with one deterministic
  `dart` pirate fighter at (1480,1000), preserving the existing
  authoritative AI and spawn/destruction/respawn event lifecycles.
- Mapped the original Space Rogue Dart's documented 245 armor to
  245 hull; shield and laser values remain explicit provisional
  balance values pending faithful directional-shield/weapon systems.
- Added lightweight procedural Three.js Dart geometry in orange with
  sweeping delta wings, pointed nose, small dark canopy, vertical
  dorsal fin, exhaust ports and the existing target-selection ring.
- Added Dart orientation, ship-model and NPC target-facing tests;
  rewrote the multi-NPC-dependent simulation and channel tests for
  the single-Dart demo, including destruction and delayed respawn.
- Left the current cockpit, player flight, twin laser hit logic,
  damage authorization and bounded AI control unchanged.

### Solar System Atlas V1 — Sun through Pluto (2026-11-02)

- Replaced the tactical sector map as the initial Atlas screen with a
  custom SOL overview displaying the Sun, eight planets and Pluto.
- Added mean astronomical distances in AU, orbital periods, selectable
  body details, differentiated colors, orbital rings, compressed radius
  projection and an inner-planets magnification.
- Preserved the working Sector 1-1 XY/Z route planner under its own tab.
  Planet selections are display-only and cannot send map coordinates.
- Added regression tests for ordering, Pluto's dwarf-planet category,
  scaling, SVG object rendering, view changes and isolation of
  existing tactical waypoint drafts.
- Documented that planet positions are schematic: no live ephemerides,
  interplanetary flight or encounter simulation has been added yet.

### Default Atlas launch instead of cockpit (2026-11-02)

- Launch `/play` with the Solar System Atlas visible from the first
  HTML paint, and call `NavigationComputer.open()` during JS boot
  after flight and laser input handlers are ready but before socket
  connection. Prevent immediate cockpit interaction while Atlas is open.
- Retain the existing `M`, `Esc` and Return to cockpit controls,
  3D/SBS renderer, world socket, server-side Sector 1-1 Dart and
  tactical route planner.
- Add regression coverage for initial open, idempotent repeated opens,
  closing the Atlas, and restoring cockpit readiness.

### Peaceful entry and SOL navigation prototype (2026-11-02)

- Disabled startup Dart spawning in the production authoritative map:
  Sector 1-1 now begins free of encounters and players cannot take NPC
  damage while examining the initial Atlas.
- Added explicit server-only NPC encounter spawn/clear APIs. Production
  encounters now end on destruction rather than restarting endlessly.
- Added `Core.Universe.Sol` and independent supervised
  `Core.Universe.Navigation`, keyed by authenticated player identity,
  with bounded game-scaled interplanetary transit, arrival and abort.
- Integrated SOL course requests and broadcasts in the Phoenix
  WorldChannel; no client-controlled player ID or AU-to-sector coordinate
  translation is accepted.
- Added Solar Atlas route controls and schematic moving transit marker,
  separate from the still-functional Sector 1-1 XYZ tactical planner.
- Updated combat fixtures and added Elixir and JS tests for peaceful
  entry, explicit encounters, Sol catalogue, route validation, progress,
  abort and server/client state isolation.

### Two real-time propulsion modes and sublight SOL cruise (2026-11-02)

- Superseded 12–120-second game-timer voyages with constant-speed
  interplanetary sublight cruise through deliberately compressed SOL
  gameplay coordinates. Accurate AU references remain separate.
- Added authoritative per-pilot SOL coordinates, distance travelled,
  fixed cruise drive speed and independent voyage state, advanced on the
  same one-second clock as all players. No clock fast-forwarding.
- Added server API guards preventing cockpit flight, target/combat and
  weapon operations while a pilot is in sublight transit.
- Engaging cruise cancels old local autopilot movement and combat lock.
- Atlas displays sublight drive speed, route progress and minute:second
  ETA; cockpit indicates that flight controls are locked during transit.
- Added V2 regression tests for sample travel times, concurrent voyages,
  sublight position interpolation and propulsion-mode exclusivity.
 
### EncounterDirector classification without tactical handoff (2026-11-03)

- Added `Core.Universe.EncounterDirector` for classification of genuine
  sensor-derived SOL close passes using NPC disposition, owning faction,
  Zone of Control and server-provided faction standing.
- Identified Sentinel-07 as a Venus patrol; preserved all six existing
  routes, schedules, cargo and player-independent movement.
- Returned encounter classification in private per-pilot navigation
  snapshots and one-time events; retained existing strategic flyby mode
  and continuous interplanetary cruise.
- Updated ordinary cockpit encounter text for neutral flyby, patrol
  attention and hostile contact; no combat/inspection promise.
- Added deterministic director tests and a hostile navigation regression.
- Test execution: not run here (Elixir/Mix unavailable); live browser
  verification remains outstanding. No faction reputation persistence,
  tactical instances, interception, random spawns or NPC combat added.


### Strategic encounter modal and pilot cruise hold (2026-11-03)

- Changed real SOL close passes from passing notifications to a
  server-authoritative, pilot-scoped travel hold with a pending decision.
- The pilot's location, voyage progress and ETA freeze during the hold.
  NPC vessel traffic and all other pilots continue independently.
- Added authenticated `solar_resolve_encounter` with strict encounter ID
  and action validation. Hail remains read-only and sensor-range checked;
  Continue resumes the original route without a position reset.
- Added centered modal encounter decisions to normal cockpit/Atlas and
  duplicated per-eye panels for SBS. Updated Atlas and helm status.
- Added regression cases for hold/reconnect state, isolation, travel
  completion after resolution, and invalid client decisions.
- No physical tactical encounter/combat or restart durability yet.
  Mix, npm, asset build and browser/HMD verification are still pending.

### Encounter regression correction (2026-11-03)

- Updated the two-pilot hold test to account for independent Mars-route traffic:
  pilot 732 can also encounter a vessel, so attempting to resolve pilot 731's
  courier ID correctly yields `:encounter_mismatch`, not `:no_pending_encounter`.
- Verify pilot 732 can resolve its own contact and continue moving while pilot
  731 remains paused. No runtime encounter behavior was changed.
- User-reported initial run: 11/12 core navigation tests, 18/18 Phoenix
  channel tests, and asset build succeeded. Revised test awaits execution.

### LAN-accessible development endpoint (2026-11-03)

- Changed the default development Bandit interface from loopback
  `127.0.0.1` to `0.0.0.0`, supporting an external SBS headset without
  requiring the former `DARKORBIT_LAN_HMD=1` launch flag.
- Added `DARKORBIT_LOOPBACK_ONLY=1` to opt into a restricted local-only
  listener on untrusted networks. Production endpoint configuration is unchanged.
- Not verified on physical headset; run from a trusted LAN and use the
  laptop's IPv4 address for remote device connections.


### Encounter popup delivery and HMD overlay (2026-11-03)

- Restored the direct `solar_encounter_started` listener in the laptop
  cockpit so its server-held encounter popup opens on first notification.
- Preserved snapshot-based reconnect recovery and keyboard-modal behaviour;
  the Atlas is inert while the popup is awaiting a decision.
- Added a filtered, read-only SOL encounter subscription for the separate
  phone headset and a per-eye alert; decisions still use the laptop's
  authenticated WorldChannel.
- Added headset view and channel privacy regression tests; no combat,
  trade or tactical travel changes were introduced.
- Tests and real headset/browser verification were not run in the
  editing environment.

### Procedural SOL encounters (2026-11-03)

- Corrected the scarcity of close-pass events after an Earth–Venus departure:
  a shared real-position traffic vessel is now launched on a converging
  route for each departure in the current playtest configuration.
- Randomized trader/patrol/raider type and meeting phase in the server.
- Added 32-ship procedural limit and 15-minute expiry, preserving the
  six scheduled ships and existing NPC independence.
- Maintained an established radio channel for the exact pilot-held
  pending contact; unrelated hails remain range-gated.
- Added collision-of-trajectories and lifecycle regressions and extended
  channel arrival test for multiple decisions. Tactical fights remain
  unimplemented; no Mix execution available in the editing environment.



### Enter real 3D combat from a hostile SOL encounter (2026-11-03)

- Added a server-validated **Engage / Enter combat** action for hostile
  and patrol-attention close passes. Neutral contacts remain unchanged.
- Instantiated one Dart-class local opponent per pilot encounter, named
  for the contacted vessel, with validated map-space spawn near the ship.
- During tactical combat only, unlock conventional cockpit controls,
  preserve frozen SOL travel progress, and keep the current real planet
  visible to avoid concealing collision hazards.
- Verified-map-victory and explicit retreat both resume the original
  interplanetary route. Retreat cleans stale target locks.
- Paired HMD now subscribes to pilot's real planetary map and remains
  display-only.
- Added core world and Phoenix channel tests. The tactical scene currently
  reuses the existing orbital region (not isolated mid-space). Tests and
  physical headset acceptance await running on the user's workstation.

- On server-confirmed pilot defeat, canceled the held SOL voyage and
  cleaned the NPC so the player can reconnect at their departure planet.
  Added authorization regression tests for defeated ships.
- Reused the original swept-wing Dart model for unique tactical NPC IDs
  and limited an encounter NPC's auto-targeting to its owner.


### Neutral trader tactical attacks (2026-11-03)

- Added an explicit **Attack vessel** encounter action for peaceful traffic,
  including procedural Harbor traders; retained existing Hail and Ignore.
- Opened server-authorized tactical combat for pending neutral flybys
  while keeping encounter ownership and held SOL cruise enforced.
- Neutral NPCs now remain passive until hit, then can retaliate; raiders
  and hostile patrol contacts still pursue immediately.
- Updated UI copy and added JS, Core World and Phoenix channel regressions.
- Trader-specific models, reputation/penalties, trade inventory outcomes
  and actual loot remain future work. Tests still require local execution.


### Scow trader hull (2026-11-03)

- Introduced **Scow** as a separate Core NPC ship definition (210 hull,
  10-damage laser, slower movement) rather than reusing Dart stats.
- Annotated existing scheduled/procedural merchant and courier traffic
  with a server-owned Scow class; surfaced it through encounter
  snapshots and authenticated tactical entry.
- Added a distinctive procedural blue, rounded-bow cargo vessel and
  Scow model selection in the shared Three.js/SBS renderer.
- Expanded Core World, traffic and Phoenix channel regression tests,
  and added Node tests for the model's identity and dimensions.
- Flight, surrender, jettison, reputation and loot behavior remain
  future work; this commit does not claim these are implemented.
- Elixir suites and physical browser/HMD verification still pending.


### Scow graphics and damage-model audit (2026-11-03)

- Corrected missing Scow graphics in the strategic close-pass preview:
  type-aware view now selects the actual new blue cargo model and
  preserves it for a pending paused encounter.
- Added the authoritative tactical NPC `ship_class` to world snapshots,
  consumed by laptop and SBS headset with a shared type resolver.
- Display selected ship class in the cockpit target HUD.
- Added end-to-end model identity, classification and preview tests;
  the code is not yet verified on a running HMD.
- Audited original Space Rogue mechanics: fore/aft shield hemispheres,
  global hull armor and disableable ship systems. Current pooled
  shield/hull damage is unchanged; detailed impact behavior is a
  future combat milestone, not part of the rendering fix.


### Course-driven Scow interception (2026-11-03)

- Tactical Scows now inherit authenticated SOL origin and destination
  instead of selecting the square `idle -> patrol` NPC pattern.
- Added server-owned `Core.NPC.CruiseRoute` projection into a safe local
  straight transit lane, avoiding planetary exclusion geometry.
- Added distinct moving `:cruise` merchant behavior: neutral ships
  do not chase; provoked ships can fire their turret while flying onward.
- Serialized stable NPC bearing and course endpoints for both desktop
  and paired SBS HMD renderers.
- On crossing the lane's endpoint, automatically remove the Scow,
  release target locks and resume the owner's held SOL voyage, including
  disconnected viewers. Strategic SOL traffic continues independently.
- Added route, AI, and end-to-end world regression tests. These tests
  have not been executed in the editing environment.


### Sunracer baseline, cargo hold and equipment locker (2026-11-03)

- Changed catalog ship 1 from placeholder Phoenix to Sunracer, retaining
  persisted account ship ID 1 and preserving future multi-ship ownership.
- Base Sunracer now has 300 armor, a 10-point built-in Garnet, a four-tonne
  cargo hold and original Forward-1/missile/drive system metadata.
- Added Beryl (15) and Sapphire (20) named upgrades; single Sunracer
  beams replace rather than stack damage, while existing DarkOrbit
  multi-slot ships retain additive equipment calculations.
- Added /equipment authenticated equipment/loadout screen, account-owned
  equip/unequip forms, and persistent C-1/C-2 selection applied to the
  next cockpit session.
- Added fixed-catalog cargo commodity storage to the existing
  inventory JSON with row-locked capacity-constrained transfers.
- Added non-suicidal Scow survival transitions: evade at 80% hull and
  surrender at 35%; accept surrender is ownership checked and resumes
  the suspended course; surrendered ships are protected from shots.
- Added unit and integration tests for baseline stats, owned inventory,
  equipment transfers, configuration activation, surrender and security.
- Directional shield physics, real cargo trading, surrender payout,
  loot reconciliation and live-session refitting are not implemented.
- Elixir/Mix tests and physical headset runs not executable in the
  editing environment.


### Active ship configuration join correction (2026-11-03)

- Phoenix WorldChannel now reads the persisted active C-1/C-2 choice
  before both player_status/2 and World.connect/3. Previously it always
  supplied configuration 1 and ignored the shipyard's activated layout.
- Updated legacy player-combat and ship-catalog assertions from
  Phoenix 4,000 / 40 to Sunracer 300 / Garnet 10, including the Dart
  shield/hull split on a successful starter laser hit.
- Added channel regression for genuinely spawning with Beryl 15 in
  configuration 2 after a server-owned activation.
- Hotbar retains stable pulse_emitter and x1_laser identifiers, but its
  visible label no longer falsely says Garnet when Beryl or Sapphire is
  equipped.
- Elixir/Mix tests remain unrun in the editing environment.


### Sunracer post-test regression cleanup (2026-11-03)

- Updated the two remaining Core.WorldTest Phoenix/40-damage expectations
  to actual Sunracer Garnet 10-damage combat: 6 shield + 4 hull damage
  per hit against the legacy Dart, and 108/237 after the second shot.
- Fixed the client entity spawn object assigning `angle` twice.
  Initial orientation now uses the server-provided numeric heading
  with route bearing as a visual fallback, while keeping
  `navigationAngle` as a separate presentation field.
- The 2026-11-03 workstation log reported Core.WorldTest 35/37 passed,
  204/204 Node tests passed, equipment controller 5/5 passed,
  world channel 21/21 passed, and successful assets.build (with
  duplicate-key warning). These changes target the two remaining
  failures and that build warning; retesting is required.

- Corrected SOL zone-boundary quadratic roots to divide scalar numerators
  instead of single-element tuples; existing TerritoryTest crossing cases
  exercise this real runtime-error path.
- Grouped default-argument declarations in Factions.patrol_directive/2
  and Security.assess/2; removed an unused collision binding and an
  unused equipment-controller test variable. The MapServer handle_call/3
  grouping warning remains and does not by itself imply a test failure.

### Mix precommit callback grouping (2026-11-03)

- Reordered only the two private laser-burst helper functions below the contiguous `handle_call/3` callback clauses in `Core.World.MapServer`. This removes Elixir's callback-clause grouping warning under `--warnings-as-errors` without changing gameplay, calculations, or routing. Mix verification remains required on the workstation.
