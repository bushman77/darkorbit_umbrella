# Architecture through Milestone E

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

## Authoritative world invariants

1. The initial `1-1` map owns all connected player and NPC positions, health,
   targets, cooldowns, AI state, destruction, and respawn queues in one
   GenServer. Clients submit intentions, never positions or combat results.
2. Movement destinations must be finite coordinates within the configured map
   boundaries. Each tick advances linearly by the connected ship's derived
   speed without overshooting.
3. A player has at most one live in-memory session. Every movement, targeting,
   and attack command resolves the session-bound entity. Disconnect removes
   the player and immediately clears NPC pursuit of that entity.
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
8. Core emits transport-neutral movement, NPC-state, targeting, laser, damage,
   destruction, respawn, and world-state events. `Darkorbit.World.PubSub`
   publishes them on `world:<map-id>` topics.

## Browser transport invariants

1. Credential login rotates the persisted account session. The game page
   issues a short-lived signed token containing that session identity; socket
   connect verifies both its signature and the still-current database session.
2. Only authenticated sockets can join `world:1-1`. A channel creates exactly
   one Core session, binds movement and combat to that session, and disconnects
   it when the channel terminates.
3. Movement payloads contain destination coordinates; targeting contains only
   an NPC ID; firing contains no combat values. Client-provided entity,
   session, damage, range, position, and cooldown values are ignored.
4. Channel join returns a full authoritative snapshot and persisted HUD data.
   Core PubSub events are forwarded to all joined clients; multiple clients
   therefore render the same tick-owned player positions.
5. The Canvas renderer interpolates displayed positions toward the latest
   server snapshots. Mouse input never changes an entity position locally, and
   visual damage updates consume authoritative laser/world events.
6. Left-click and click-and-hold remain dedicated to pointer navigation.
   Right-click selects a rendered NPC, the target-nearest button is the
   accessible alternative, and Space or the fire button submits a laser intent.
7. All included graphics are original placeholders. A versioned client catalog
   separates ships, NPCs, lasers, explosions, drones, and backgrounds so later
   art changes do not alter networking or simulation code.

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
concurrent attacks, dead-player rejection, and disconnect cleanup. Channel
integration tests additionally cover signed socket authentication, map
authorization, spoofed combat values, multiplayer combat broadcasts, and
simultaneous players. JavaScript tests cover pointer-navigation preservation,
target filtering/hit testing, and authoritative health updates.

## Known baseline limitations

- The full combat acceptance flow and two-player observation have not been
  manually verified in browser sessions.
- Destroyed player respawning, ammunition, loot, rewards, PvP, portals,
  spatial partitioning, persistence/recovery for live map state, and multi-node
  world ownership are not implemented.
- Catalog values and the starting map are provisional placeholder game data.
- The existing dependency lock must be reviewed regularly with `mix hex.audit`.
  Dependency advisories are release blockers for an internet-facing server.

## Next vertical slice

After manual browser acceptance, the next combat slice can add explicit player
recovery and server-owned rewards/ammunition while retaining map-process
authority and keeping persistence operations outside the simulation tick.
