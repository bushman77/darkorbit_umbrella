# Architecture through Milestone E.2.2

## Umbrella boundaries

- `apps/core` owns configurable game-data catalogs, pure stat, movement,
  combat, and NPC decision mechanics, player sessions, and the supervised OTP
  world runtime. It has no Phoenix, Ecto, or PostgreSQL dependency.
- `apps/darkorbit` owns PostgreSQL persistence and the account, fleet,
  inventory, loadout, preference, and title domains. It adapts persisted
  loadouts into pure core stats and delivers core events through Phoenix
  PubSub.
- `apps/darkorbit_web` owns browser-session authentication, the authenticated
  game socket and world channel, HTTP routes, and the Canvas 2D client. It
  translates browser intentions and Core events without owning simulation
  mechanics.

`Darkorbit.Application` starts the repository, DNS discovery, Phoenix PubSub,
and then `Core.World.Supervisor`. The world supervisor owns its Registry,
session manager, and configured map processes as one ephemeral consistency
boundary. `DarkorbitWeb.Application` separately supervises web telemetry and
the endpoint.

## Persistent player-state invariants

1. `Darkorbit.Accounts.register_account/1` accepts only username, email, pilot
   name, and password. Currency, progression, faction, verification, session,
   and active-ship values are server controlled.
2. Registration inserts the account, one starter ship, both loadout
   configurations, inventory, settings, and titles in one `Ecto.Multi`. Any
   provisioning failure rolls back the account and all related rows.
3. Fleet ownership is represented only by `player_ships`; the former duplicate
   ownership list in inventory is not used. Adding an already-owned ship is
   idempotent, restricted to catalog definitions, and always ensures
   configurations 1 and 2 exist.
4. Inventory stack mutations lock the account's `player_equipment` row with
   `FOR UPDATE`. Counts cannot become negative and unknown equipment ids are
   rejected.
5. Loadout mutations require the acting account id. The owned loadout and
   inventory are locked, slot bounds and ship capacity are checked, and item
   removal/replacement/return happen in one transaction.
6. Player and ship foreign keys cascade on account deletion. Unique indexes
   enforce one inventory/settings/title row per account, one ship definition
   per account, and one of each loadout configuration per owned ship.
7. Database checks enforce valid faction ids, non-negative persistent
   balances/experience, positive levels, ship and rank ids, and configuration
   numbers 1 or 2.

## Ship statistics invariants

1. Ship, laser, speed-generator, and shield definitions are configurable game
   data. The initial values are placeholders until balancing is verified.
2. Hit points, shields, absorption, regeneration, speed, damage, and cargo are
   derived by pure functions. Computed values are never persisted.
3. Equipment ids and slot compatibility come from the catalog; a laser cannot
   occupy a generator slot, and only the catalog-defined ship capacity is
   usable.
4. Configurations 1 and 2 are calculated independently from their actual
   equipped loadout state.
5. The Phoenix has a catalog-defined built-in pulse emitter. It gives existing
   and new pilots non-zero base damage without granting or duplicating a
   persistent inventory item during world connection.

## Pure combat and NPC invariants

1. `Core.Combat` validates entity kinds, alive state, range, simulation-tick
   cooldowns, and server-owned damage. Negative damage is normalized to zero.
2. Shield absorption is clamped to the valid range. Applied shield and hull
   damage cannot exceed the target's remaining values, and neither resource
   can fall below zero.
3. Only player-to-NPC and NPC-to-player targets are valid. PvP, NPC friendly
   fire, and client-supplied combat statistics are rejected by construction.
4. `Core.NPC.Catalog` contains configurable definitions and spawn/respawn data.
   The initial original enemy is the `Rift Skirmisher`; its values are
   provisional.
5. `Core.NPC.AI` is pure and bounded. Its `idle`, `patrol`, `pursue`, `attack`,
   and `destroyed` transitions use deterministic patrol points and tick-based
   attack readiness, with no pathfinding or wall-clock dependency.
6. `Core.Combat.ActionCatalog` defines the ten-slot action surface as data.
   Assigned actions expose a stable ID, action type, and activation mode. Slot
   1 is the toggle-mode X1 ammunition action and the remaining slots are
   empty; activating an empty slot has no inventory or ammunition side effect.
   X1 references, but is not, the server-defined Phoenix pulse-emitter weapon.
   The emitter continues to own its 700 ms cooldown, while player damage still
   comes from the connected ship's server-derived combat statistics.

## Authoritative world invariants

1. The initial `1-1` map owns all connected player and NPC positions, health,
   targets, cooldowns, AI state, destruction, and respawn queues in one
   GenServer. Clients submit intentions, never positions or combat results.
2. Movement destinations must be finite coordinates within the configured map
   boundaries. Each tick advances linearly by the connected ship's derived
   speed without overshooting.
3. A player has at most one live in-memory session. Every movement, targeting,
   engagement, action, and attack command resolves the session-bound entity.
   Disconnect removes the player and immediately clears NPC pursuit of that
   entity.
4. Tick duration, automatic ticking, map definitions, and the event sink are
   runtime configuration. Tests disable timers and drive ticks synchronously.
5. NPC IDs use the reserved `npc:<map>:<type>:<spawn-slot>` namespace. Joins
   reject an entity ID already used by either a player or NPC.
6. NPC spawns are deterministic. Destruction removes an NPC from snapshots and
   records a tick deadline; respawn recreates the catalog-defined entity at its
   original spawn without a database query.
7. The map GenServer serializes simultaneous attacks, so a successful attack
   updates the cooldown before another command can run. Destroyed targets are
   removed or marked dead before subsequent commands are evaluated.
8. Player `target_id` is selection only; `engaged_target_id` is the explicit
   combat lifecycle. The map process owns one atomic laser toggle used by both
   the direct control command and X1 action activation. Starting validates the
   selected live NPC and weapon; stopping clears only `engaged_target_id`, so
   the selected target remains available for a later resume. The legacy
   explicit engage and clear/disengage operations remain available, with the
   latter continuing to clear both states for Escape and explicit cancellation.
   Engaging never creates a timer or process. Each bounded map tick attempts at
   most one eligible attack per engaged player, preserves engagement through
   cooldown or temporary range failure, and clears it when either participant
   or the target identity becomes invalid.
9. Combat does not replace movement state. Players retain destinations and
   continue moving at normal server-owned speed while engaged; firing never
   teleports or steers a ship into range.
10. NPC destruction clears every matching selection and engagement before the
    deterministic spawn slot can respawn. The recreated NPC cannot inherit the
    previous lock even though its catalog spawn-slot ID is stable.
11. Core emits transport-neutral movement, NPC-state, targeting, engagement,
    laser, damage, destruction, respawn, and world-state events.
    `Darkorbit.World.PubSub` publishes them on `world:<map-id>` topics.

## SOL tactical merchant invariants

1. A tactical Scow is a temporary map actor leased to one authenticated pilot
   but retains the strategic vessel ID, voyage identity, faction attribution,
   cargo settlement boundary, origin, destination, and projected course.
2. Neutral selection and attack intent do not provoke a merchant. Only a
   server-confirmed weapon impact marks that exact tactical lease as provoked;
   its target list then contains only the owning pilot.
3. Scows remain in `:cruise` or `:evade` while defending. Their turret may
   generate one cooldown-eligible action without replacing the existing route
   destination or switching to Dart pursuit behavior.
4. NPC AI evaluates range against the post-player-movement tick snapshot.
   MapServer carries that authoritative firing position into resolution, then
   rechecks current alive state, target validity, cooldown and range against
   that same origin before applying damage and publishing `:laser_fired`.
   NPC route movement later in the tick therefore cannot invalidate a shot
   that was legal when selected.
5. Scow encounter placement first tries front, side and rear positions 340
   units from the pilot. Every candidate passes normal map-boundary and
   planetary-exclusion checks; the prior 520-unit positions remain fallbacks
   when all preferred positions are unsafe. No ship is teleported after the
   encounter starts.
6. At 80% remaining hull or below a Scow retains its destination and enters
   faster evasion. At 35% or below it surrenders, clears its target and
   destination, and stops. Surrendered or destroyed actors cannot generate or
   resolve attacks.
7. The current private tactical-lease model authorizes each pilot and weapon
   against only that lease's NPC. It prevents another encounter's Scow from
   targeting or damaging the wrong pilot; genuinely shared tactical combat is
   a separate future architecture.

## Browser transport invariants

1. Credential login rotates the persisted account session. The game page
   issues a short-lived signed token containing that session identity; socket
   connect verifies both its signature and the still-current database session.
2. Only authenticated sockets can join `world:1-1`. A channel creates exactly
   one Core session, binds movement and combat to that session, and disconnects
   it when the channel terminates.
3. Movement payloads contain destination coordinates; targeting contains only
   an NPC ID; engagement, laser toggle, and disengagement contain no combat
   values; action activation contains a bounded slot number. Client-provided
   entity, session, target, damage, range, position, and cooldown values are
   ignored by these commands.
4. Channel join returns a full authoritative snapshot and persisted HUD data.
   Core PubSub events are forwarded to all joined clients; multiple clients
   therefore render the same tick-owned player positions.
5. The Canvas renderer interpolates displayed positions toward the latest
   server snapshots. Mouse input never changes an entity position locally, and
   visual damage updates consume authoritative laser/world events.
6. Primary pointer-down first restores gameplay focus and then hit-tests live
   NPCs with the same world-to-screen transform and catalog dimensions used by
   rendering. An NPC hit submits only target selection; empty-space clicks
   enter the existing pointer-capture navigation path, including click-and-hold
   retargeting. Buttons, drag handles, and editable fields retain their native
   keyboard behavior and are excluded from combat shortcuts.
7. The renderer reads replicated `engaged_target_id` for every player. Combat
   facing is recalculated from interpolated player/target positions each frame
   and smoothed across angle wrap; navigation facing remains independently
   tracked and becomes authoritative visually as soon as engagement clears.
8. The hotbar is rendered from structured server definitions. Number-row keys
   and clicks submit the same slot activation without client-side slot behavior
   branches. `ControlLeft` and `ControlRight` submit the same authoritative
   laser toggle as X1; repeat keydowns and unintended Ctrl chords are ignored.
   Space is reserved for a future single-shot rocket and reports that the action
   is unavailable without submitting an attack. Esc explicitly disengages and
   clears selection. `AUTOFIRE`, `STANDBY`, toggle-action active styling, and
   cooldown shading derive from authoritative engagement and simulation-tick
   state rather than optimistic client flips.
9. Right-click selection and the target-nearest button remain available as
   alternatives to left-click selection.
10. The minimap uses the same pointer-navigation lifecycle as the main canvas,
    but projects pointer coordinates through its letterboxed authoritative map
    bounds. It submits destination intentions only while the HUD is locked, the
    panel is visible and expanded, and the world channel is joined. Hold input,
    cancellation, and pointer-capture cleanup do not mutate combat state.
11. All included graphics are original placeholders. A versioned client catalog
    separates ships, NPCs, lasers, explosions, drones, and backgrounds so later
    art changes do not alter networking or simulation code.

## Cockpit presentation invariants

1. `CockpitWindowManager` is a presentation-only boundary. It owns window
   position, visibility, collapsed state, minimap width, focus order, editing
   lock state, and local persistence; it does not submit or mutate movement,
   targeting, combat, health, cooldown, or entity state.
2. Each managed panel has a stable `data-cockpit-window` identifier and one
   dedicated header handle. Pointer dragging is available only when the HUD is
   unlocked, uses pointer capture, and is cancelled on pointer cancellation,
   capture loss, window blur, hidden documents, lock, or teardown.
3. Cockpit pointer events stop at the panel boundary. Normal panel buttons stay
   interactive while locked. The main space canvas and the minimap canvas are
   separate pointer-navigation surfaces and share no local movement state.
4. Layout payload version 1 stores only finite window coordinates, minimap
   width, visibility, collapsed state, and HUD lock state under
   `darkorbit:cockpit-layout:v1:player:<numeric-player-id>`. Authentication
   tokens and world state are never persisted. Parse, schema, quota, and
   storage-access failures fall back without interrupting gameplay. Payloads
   created before minimap sizing retain their existing fields and receive the
   current default width.
5. Desktop coordinates are clamped against header and hotbar safe areas on
   restore, drag, keyboard movement, collapse, visibility changes, and resize.
   Floating minimap width changes in 40-pixel steps, is bounded from 192 to 520
   pixels, and is additionally clamped to the available viewport. Below 720
   CSS pixels or 620 CSS pixels in height, windows enter a horizontally
   scrollable dock, dock sizing overrides floating width, and drag input is
   disabled.
6. Ship status and target information consume the same authoritative entities
   already used by the renderer. Collapsing or hiding presentation cannot alter
   selection, engagement, attacks, movement, cooldowns, or server state.
7. `MinimapRenderer` owns the sole minimap canvas and its resize-observer
   lifecycle. It projects interpolated entity positions into authoritative map
   boundaries at a throttled 20-frame-per-second ceiling. A separate
   `PointerNavigation` instance converts valid canvas gestures back through the
   same projection and submits destination intentions through the joined world
   channel; the server remains authoritative for validation and movement.
8. The action hotbar remains outside the managed window stage and anchored at
   bottom center. The window-manager keyboard handler consumes only arrow keys
   on focused drag handles while unlocked, leaving combat and hotbar shortcuts
   to the existing guarded control path.
9. Minimap decrease and increase controls remain available while the HUD is
   locked and cannot begin a header drag. The resize observer updates canvas
   backing dimensions after a floating-width change, so navigation projection
   continues to use the rendered CSS dimensions.

## Build and release artifact boundaries

1. `apps/darkorbit_web/assets/` is the Phoenix browser source package. Its
   `package.json` and `package-lock.json`, CSS, JavaScript, tests, and vendored
   source modules are tracked; `node_modules/` and accidental root-level
   command-token files are ignored.
2. Undigested files in `apps/darkorbit_web/priv/static/` are deployable source
   inputs. Original game SVG artwork, the favicon, and `robots.txt` stay under
   source control. `mix assets.build` writes compiled CSS/JavaScript under the
   ignored `priv/static/assets/` directory.
3. `mix assets.deploy` runs the minified Tailwind and esbuild pipelines and
   then `phx.digest`. The resulting cache manifest, gzip copies, and 32-hex
   fingerprinted copies are reproducible release output and are ignored rather
   than tracked. Release construction must run the deploy task before booting
   the production endpoint that consumes `cache_manifest.json`.
4. The umbrella root is not an npm package and therefore owns no npm lockfile.
   Dependency locks remain scoped to their consumers: `mix.lock` for the
   umbrella, the Phoenix asset `package-lock.json`, the Tauri
   `package-lock.json`, and Tauri's `src-tauri/Cargo.lock`.
5. `clients/tauri/` tracks launcher UI/Rust source and its package locks.
   Node dependencies, generated bindings, Rust targets, and local package
   output remain under ignored `node_modules/`, `src-tauri/gen/`,
   `src-tauri/target/`, and `dist/` boundaries. The Linux, Windows, and signed
   release workflows package from those generated locations and upload them as
   workflow/release artifacts, not repository source.
6. Signed desktop publishing remains an explicitly dispatched `sbs`-branch
   operation guarded by signing secrets and version matching. Local validation
   may build unsigned installers, but it cannot substitute for the uninvoked
   signed multi-platform release workflow.

## Test baseline

The test suite covers complete registration provisioning, rejection of
client-controlled authoritative values, authentication and company selection,
idempotent ship provisioning, ownership-scoped active ships, inventory bounds,
slot validation, atomic equipment replacement, and cross-account loadout
authorization. Multi-connection regression tests issue simultaneous inventory
withdrawals and simultaneous equips to prove that one item cannot be consumed
or equipped twice. Pure tests cover catalogs, stat aggregation, equipment
constraints, boundaries, movement, combat calculations, NPC definitions, and
AI transitions. Headless tests cover deterministic NPC spawning/movement,
range and cooldown enforcement, damage/destruction/respawn, repeated and
concurrent attacks, persistent engagement, automatic cooldown cadence,
out-of-range pause/resume, movement during combat, destruction/respawn lock
clearing, dead-player rejection, action validation, cancellation, and
disconnect cleanup. SOL merchant regressions additionally cover neutral
non-aggression, confirmed-hit provocation, decision-time range preservation,
Garnet damage/events, exact cooldown readiness, out-of-range rejection,
course and evasive movement, surrender/destruction, settlement preservation,
and per-pilot tactical isolation. Laser-control regressions additionally cover direct and
X1 alternating toggles, selection-preserving stop/resume, clear semantics,
cooldown preservation across toggles, sequential NPC engagements, invalid or
empty actions, missing targets, unauthorized sessions, and destroyed players.
Channel integration tests additionally cover signed socket authentication, map
authorization, spoofed combat values, structured hotbar commands, multiplayer
engagement replication, combat broadcasts, and simultaneous players.
JavaScript tests cover pointer-navigation preservation, left-click selection
without movement, render-dimension hit testing, all ten number keys, both Ctrl
keys, held-key and modifier guards, reserved Space behavior, metadata-driven
active state, combat-facing precedence, moving-target rotation,
navigation-facing restoration, and authoritative health updates. Cockpit tests
additionally cover drag lock state, collapse,
visibility, reset, versioned persistence, corrupt storage fallback, clamping,
responsive docking, pointer cleanup, canvas isolation, keyboard access,
reduced motion, and minimap projection, throttling, and lifecycle cleanup.
Minimap-size regressions additionally cover locked controls, 40-pixel steps,
persistence and reload, legacy payload preservation, reset, configured and
viewport bounds, responsive docking, and the existing continuous steering and
combat-isolation paths. The authenticated game-page test asserts three stable
cockpit windows, exactly one minimap canvas, and both sizing controls.

## Known baseline limitations

- Milestone E.1 navigation, NPC targeting, persistent laser engagement, combat
  facing, and circular combat maneuvering were manually verified. Broader
  two-player observation remains deferred.
- The E.2.1/E.2.2 cockpit, minimap navigation, and minimap sizing have not been
  manually verified in a browser at the target desktop and mobile viewport
  sizes.
- The revised Ctrl/X1 toggle, Space reservation, focus restoration, and
  stop/resume flow have not been manually verified in a browser.
- Destroyed player respawning, configurable or consumable ammunition beyond
  the non-inventory X1 identity, rockets, loot, rewards, PvP, portals, spatial
  partitioning, persistence/recovery for live map state, and multi-node world
  ownership are not implemented.
- Catalog values and the starting map are provisional placeholder game data.
- The existing dependency lock must be reviewed regularly with `mix hex.audit`.
  Dependency advisories are release blockers for an internet-facing server.

## Next vertical slice

Manual browser acceptance should verify layout persistence, minimap sizing,
responsive dock transitions, continuous minimap steering, Ctrl/X1 alternating
toggle behavior, target-preserving stop/resume, Space messaging, and canvas
focus restoration while retaining map-process authority. Multiplayer
expansion, broader two-browser validation, player recovery, and server-owned
rewards or consumable ammunition remain deferred.
