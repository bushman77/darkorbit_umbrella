# Space Nova — Orbital bases and forward refineries V1

This is the first **server-authoritative** dock/refinery simulation.
It is deliberately not yet a player-controlled station docking UI.

## Automated verification

From the umbrella root:

```sh
git status --short
git pull --ff-only origin sbs
mix test apps/core/test/core/universe/space_bases_test.exs
mix test apps/core/test/core/universe/space_bases_navigation_test.exs
mix test
cd apps/darkorbit_web/assets
npm test
```

No new database migration is needed for this first refineries slice.
Refinery stock is currently live supervised SOL state (not persisted to
PostgreSQL across a full server restart).

## What should happen

- **Every registered planet and Pluto:** One named Orbital Base and one
  Forward Refinery; each has **three docking bays**. There is no Sun port.
- **Scheduled departures:** Load only industrial goods available in the
  actual departure refinery. An empty refinery produces empty or partially
  loaded ships; it does not magically refill a manifest.
- **Arrivals:** One ship occupies one bay. The refinery receives the ship's
  inbound goods, then loads its declared return manifest from local stocks.
  The vessel leaves the bay after a 45-second service window.
- **Full bays:** A fourth arriving civilian waits with its cargo onboard.
  Its manifest cannot unload until a real bay becomes free.
- **Refinery output:** Every 60 seconds the planet's provisional industrial
  profile generates bounded quantities of local goods.
- **Combat:** Existing strategic-to-tactical vessel identity, surrender,
  cargo seizure, faction consequences and disabled-ship behavior remain
  intact; seized cargo is not restored by docking.

## Visual/manual check

1. Start Phoenix again after pulling and compiling source.
2. Navigate into an actual `sol:earth` or `sol:<planet>` orbital region.
   The old isolated `1-1` test sector is **not** a planetary map.
3. In Atlas's flight telemetry panel, inspect **Orbital Base** and
   **Forward Refinery**. The bay count should reflect occupied docks.
4. In the conventional cockpit, locate the fixed low-poly orbital hub
   outside the planet's collision exclusion zone. The paired phone's SBS
   cockpit uses the same server-published station position.
5. The base currently has a ring, central hub, three bays and industrial
   tanks. This is a **visual structure**, not yet a docking collider.
6. To see ships use bays in the strategic simulation, leave the SOL world
   clock running. Regular shipping continues with zero logged-in pilots.

## Next: physical docked-ship presentation and transactions

- Put a real Scow mesh at each occupied bay and animate approach/departure.
- Add player approach corridor, permission and safe-speed checks.
- Expose authenticated refinery trading/buy-sell transactions and
  faction-controlled spaceport fees.
- Persist base inventory, berth occupancy and trade voyages to Postgres.

Avoid mistaking a visible empty bay for a missing trader. The strategic
merchant moves over the shared SOL clock, and not every planet has a
vessel docked at all times.
