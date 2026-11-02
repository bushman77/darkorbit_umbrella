# Planetary spherical Zones of Control — Geometry V1

Status: pure Core geometry slice. Not integrated into encounter spawning,
interception, reputation, patrol AI, the browser Atlas or persistent navigation.

## Contract

Every navigable SOL planet (including Pluto) has one faction and a spherical
Zone of Control (ZOC) centred on the planet's **server-owned SOL game position**.
The Sun has no faction ZOC.

`Core.Universe.Territory.zones/1` returns the initial catalog.
`classify(position, zones)/2` reports the independent claims at one position:

- `:unclaimed`: no sphere contains the position. Pirate and independent
  factions may operate here; the absence of planetary claims does not give
  pirates automatic exclusive ownership.
- `:controlled`: exactly one planetary sphere contains the position.
- `:contested`: at least two planetary spheres contain the position.

Claims expose their faction, distance to centre, normalized distance
(`distance / radius`), and geometric influence (`1 - normalized_distance`).
Influence is *not* a probability. Later security code will combine distance
with patrol assets, routes, faction standing and diplomatic rules.

`crossings(from, to, zones)/3` returns deterministic, ordered `:entered`
and `:exited` events for a straight 3D travel segment. This is the intended
future hook for patrol evaluation as server time advances. It neither interrupts
travel nor generates any encounter by itself.

Both the query and the segment use **game kilometres** in the SOL coordinate
frame. Local Sector 1-1 XYZ coordinates must never be passed to this module
without an explicit future region transfer. Invalid coordinates, zones and
duplicate zone IDs are rejected. Boundaries belong to their containing zone;
a mere tangent is not a crossing. Segment endpoints do not create crossing
events, preventing duplicates at a shared tick boundary. A future event
consumer must compare membership when a route starts or ends on a boundary.

## Radius policy

The earlier aligned-planet illustration is conceptual. Nine spheres with
one radius each cannot independently reach the orbital halfway line both
inward and outward when orbital gaps differ. Nor can the illustration
guarantee overlaps while planets lie at different orbital angles.

For V1, the default **provisional** radius for each body is 53% of the
distance to its nearest adjacent planet **in the existing compressed,
fixed SOL gameplay layout**. This produces modest overlaps where actual 3D
spheres intersect, plus natural gaps of unclaimed space. It is **not**
derived from real AU-to-kilometre conversion, and doesn't guarantee all
adjacent pairs overlap. Use `radii_km: %{"earth" => ...}` to tune an
individual radius from authoritative server configuration. Do not accept
radius settings from a browser request.

The existing `Core.Universe.Sol` positions have fixed illustrative phases,
not live orbital ephemerides. When the game introduces shared planetary
motion, supply authoritative time-dependent centres while retaining the same
containment and crossing rules. Keep the radii under server control and
test overlap behaviour as body separations change.

## Next implementation phases

1. Faction identity, player reputation and diplomacy; influence/security
   weighting independent of the geometry.
2. Long-distance detection and patrol presence within these spheres,
   including contested-area patrols from each claimant.
3. Encounter classification (passive, optional, forced interception).
4. Cruise interdiction and player decision states, preserving authoritative
   elapsed time, distance, multiplayer presence, and safe reconnect behaviour.

Do not simply spawn an NPC on a geometry crossing: detection and interception
success must be resolved independently from territorial membership.

## Verification

From the umbrella root, once the branch is on a machine with Elixir:

```sh
mix format --check-formatted
mix test apps/core/test/core/universe/territory_test.exs
mix precommit
```

The implementation branch was authored remotely; these commands still need
to be executed on the developer's machine.
