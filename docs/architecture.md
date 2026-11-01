# Architecture baseline through Milestone C

## Umbrella boundaries

- `apps/core` owns configurable game-data catalogs, pure stat and movement
  mechanics, player sessions, and the supervised OTP world runtime. It has no
  Phoenix, Ecto, or PostgreSQL dependency.
- `apps/darkorbit` owns PostgreSQL persistence and the account, fleet,
  inventory, loadout, preference, and title domains. It adapts persisted
  loadouts into pure core stats and delivers core events through Phoenix
  PubSub.
- `apps/darkorbit_web` owns the Phoenix endpoint and browser-facing layer. It
  currently contains the generated web shell; gameplay Channels and the canvas
  client have not been implemented yet.

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

## Authoritative world invariants

1. The initial `1-1` map owns all connected entity positions in one GenServer.
   Clients submit destinations, never positions.
2. Movement destinations must be finite coordinates within the configured map
   boundaries. Each tick advances linearly by the connected ship's derived
   speed without overshooting.
3. A player has at most one live in-memory session. Map commands verify the
   session bound to the entity, and disconnect removes both session and entity.
4. Tick duration, automatic ticking, map definitions, and the event sink are
   runtime configuration. Tests disable timers and drive ticks synchronously.
5. Core emits transport-neutral events. `Darkorbit.World.PubSub` publishes
   `:entity_joined`, `:entity_left`, `:movement_started`, and `:world_state` on
   `world:<map-id>` topics.

## Test baseline

The test suite covers complete registration provisioning, rejection of
client-controlled authoritative values, authentication and company selection,
idempotent ship provisioning, ownership-scoped active ships, inventory bounds,
slot validation, atomic equipment replacement, and cross-account loadout
authorization. Multi-connection regression tests issue simultaneous inventory
withdrawals and simultaneous equips to prove that one item cannot be consumed
or equipped twice. Pure tests cover catalogs, stat aggregation, equipment
constraints, boundaries, and movement. A headless integration test connects a
persisted player's active ship, moves it across the map, and observes PubSub
world-state events.

## Known baseline limitations

- The Phoenix app has no player authentication UI, game socket protocol,
  Channels, LiveView administration, or canvas client yet.
- There is no combat, NPC, portal, spatial partitioning, persistence/recovery
  for live map state, or multi-node world ownership yet.
- Catalog values and the starting map are provisional placeholder game data.
- The existing dependency lock must be reviewed regularly with `mix hex.audit`.
  Dependency advisories are release blockers for an internet-facing server.

## Next vertical slice

The next completed vertical slice should add a minimal authoritative combat
loop (targeting, cooldowns, and damage) or expose the current movement protocol
through an authenticated Phoenix Channel. Either slice should continue using
pure core mechanics and keep clients limited to submitting intentions.
