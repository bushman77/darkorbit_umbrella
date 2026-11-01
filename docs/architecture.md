# Architecture baseline

## Umbrella boundaries

- `apps/core` is reserved for deterministic simulation mechanics and OTP world
  runtime. It is currently the next implementation target.
- `apps/darkorbit` owns PostgreSQL persistence and the account, fleet,
  inventory, loadout, preference, and title domains.
- `apps/darkorbit_web` owns the Phoenix endpoint and browser-facing layer. It
  currently contains the generated web shell; gameplay Channels and the canvas
  client have not been implemented yet.

`Darkorbit.Application` supervises the repository, DNS discovery, and Phoenix
PubSub. `DarkorbitWeb.Application` separately supervises web telemetry and the
endpoint. This keeps the persistent domain usable without coupling it to the
web process tree.

## Persistent player-state invariants

The stabilized domain enforces these rules:

1. `Darkorbit.Accounts.register_account/1` accepts only username, email, pilot
   name, and password. Currency, progression, faction, verification, session,
   and active-ship values are server controlled.
2. Registration inserts the account, one starter ship, both loadout
   configurations, inventory, settings, and titles in one `Ecto.Multi`. Any
   provisioning failure rolls back the account and all related rows.
3. Fleet ownership is represented only by `player_ships`; the former duplicate
   ownership list in inventory is not used. Adding an already-owned ship is
   idempotent and always ensures configurations 1 and 2 exist.
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

## Test baseline

The domain tests cover complete registration provisioning, rejection of
client-controlled authoritative values, authentication and company selection,
idempotent ship provisioning, ownership-scoped active ships, inventory bounds,
slot validation, atomic equipment replacement, and cross-account loadout
authorization. Multi-connection regression tests issue simultaneous inventory
withdrawals and simultaneous equips to prove that one item cannot be consumed
or equipped twice.

## Known baseline limitations

- `apps/core` is still the generated placeholder; no map, movement, spatial,
  combat, NPC, session, or simulation runtime exists yet.
- The Phoenix app has no player authentication UI, game socket protocol,
  Channels, LiveView administration, or canvas client yet.
- Ship ids and starter slot capacities are provisional internal definitions;
  the catalog and pure derived-stat engine belong to Milestone B.
- The existing dependency lock must be reviewed regularly with `mix hex.audit`.
  Dependency advisories are release blockers for an internet-facing server.

## Next vertical slice

Milestone B should introduce a data-driven ship and equipment catalog in the
domain application, pure derived-stat calculation, configuration-aware slot
rules, and tests for hit points, shields, absorption, regeneration, speed,
damage modifiers, and cargo. Runtime world processes should consume those pure
stats in Milestone C rather than duplicating persisted computed values.
