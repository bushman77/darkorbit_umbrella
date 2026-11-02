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
