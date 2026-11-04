# World stream delta_v1 (experimental, SBS)

The authoritative `Core.World.MapServer` still simulates and broadcasts
complete world snapshots every 100 ms. The authenticated Phoenix
`DarkorbitWeb.WorldChannel` now has a **negotiated**, transport-only
`delta_v1` mode. Older clients keep receiving `world_state` untouched.
All changes remain server-owned.

## Protocol

Join `world:<map_id>` with `{"stream":"delta_v1"}`. Successful joins
include `stream:"delta_v1"` and the existing complete `map` snapshot.
Subsequent `world_delta` events contain:

```json
{
  "base_tick": 37,
  "tick": 38,
  "entities": [{"id": 17, "position_3d": {"x": 2, "y": 3, "z": 4}}],
  "removed": [],
  "changes": {}
}
```

`entities` carries only changed top-level entity fields (new entities
are complete). `removed` carries despawned actor identities.
`changes` carries changed top-level map fields such as warnings. IDs
and combat condition still originate exclusively from the server.

The JavaScript `WorldStreamDelta` joins each sparse patch against its
last complete reconstructed snapshot. `base_tick` must equal the
client's last authoritative tick. A gap triggers `world_resync`, which
returns a complete map from the channel's **authenticated map**; any
client-supplied map ID is ignored. Old queued ticks are ignored after
resync. Channel reconnects start from a fresh join snapshot.

Frequent `movement_started` events become compact `movement_delta`
events for opted-in clients. These are presentation previews only and
**do not** mutate the authoritative tick baseline. Steering is not
delayed or throttled by replication. Successful `flight_controls`
responses are reduced to an acknowledgment rather than resending a
whole entity. Legacy clients still receive their original event names
and response shapes.

## Compatibility and scope

- The existing browser and Tauri desktop client share the updated
  `client.js`, and negotiate delta_v1 automatically.
- Unmodified older clients use full snapshots; no version negotiation
  is required to preserve them.
- Helmet viewers still receive full `world_state` for now. That is a
  separate bandwidth optimization because helmet rendering is read-only.
- SOL navigation/contact updates, laser/combat events and asset delivery
  are unchanged in V1.
- Compression and binary schemas are deliberately deferred until
  byte accounting and real gameplay validate this baseline.
- A failed resync forces reconnection rather than silently applying
  incorrect positions or combat data.

## Tests and measurement

```sh
cd apps/darkorbit_web/assets
npm test
cd ../../..
mix test apps/darkorbit_web/test/darkorbit_web/world_stream_delta_test.exs
mix test apps/darkorbit_web/test/darkorbit_web/channels/world_channel_test.exs
```

The Elixir unit test measures serialized `Jason.encode!/1` byte sizes
for the same snapshot versus delta, confirming a reduction in its
synthetic test case, **not** a measured real-world percentage.
For production-capacity planning, measure actual bytes/second separately
for idle flight, sustained mouse steering, a Scow encounter and multiple
ships using browser or WebKitGTK network diagnostics.

At scale, a future refinement should calculate map deltas once per
MapServer tick instead of once per subscribed channel to reduce
CPU use, while retaining per-subscriber resync and privacy filtering.
