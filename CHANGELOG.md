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
- Manual browser verification was not performed; the acceptance flow and two-browser observation remain required before graphical sign-off.

#### Limitations

- Slots 2 through 0 intentionally have no assigned action. Ammunition, rockets, abilities, consumables, and equipment assignment remain future work.
- Destroyed player recovery, rewards, loot, PvP, and persistent/multi-node live world state remain out of scope.
