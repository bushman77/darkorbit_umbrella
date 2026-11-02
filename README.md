# Darkorbit Umbrella

An experimental Elixir/OTP and Phoenix space-MMO server. The server is being
built as an authoritative game system: clients submit intentions, while
identity, ownership, inventory, equipment, progression, economy, and world
state are validated and owned by the server.

The completed vertical slice includes persistent player-state domains, a
deterministic ship-stat engine, a supervised authoritative starting map,
server-owned NPC combat, and an authenticated multiplayer Canvas 2D browser
client for sector 1-1.

## Requirements

- Elixir 1.15 or newer with a compatible Erlang/OTP release
- PostgreSQL 14 or newer
- A local `postgres` role with password `postgres` for the checked-in
  development and test configuration, or equivalent local config overrides

Production reads `DATABASE_URL`, `SECRET_KEY_BASE`, `POOL_SIZE`, `PORT`, and
optionally `ECTO_IPV6` from the environment. Never commit production secrets.

## Development

From the umbrella root:

```console
mix setup
mix phx.server
```

The setup alias fetches dependencies, creates and migrates `darkorbit_dev`,
seeds two playable pilots, and installs/builds the browser assets. Open
<http://localhost:4000> after the server starts, choose **Launch browser
client**, and sign in with either development account:

```text
demo_pilot / launch-sector-11
wing_pilot / launch-sector-11
```

Open a normal and private browser window with one account in each to see both
ships and the same NPC encounter. Left-click or hold empty space in the
viewport to fly, select an NPC without firing, then press Ctrl, press 1, or use
**Toggle laser** to start and stop X1 automatic fire. Escape clears the target.
Space is reserved for a future single-shot rocket and currently reports that
the action is unavailable. The server validates each intention and broadcasts
tick-owned positions, engagement, health, damage, destruction, and respawning
back to all clients.

Useful commands:

```console
mix test
mix precommit
mix hex.audit
```

`mix precommit` compiles with warnings treated as errors, removes unused lock
entries, formats the project, and runs the complete umbrella test suite. The
test aliases create and migrate `darkorbit_test` automatically. Run
`mix hex.audit` before releases to check the locked Hex packages against current
retirements and security advisories.

The game transport uses `world:1-1` on `/socket`. Browser sessions issue a
short-lived signed socket token. Channel commands contain only movement,
target-selection, target-clearing, and laser-fire intentions. Core owns
sessions, map bounds, positions, health, damage, cooldowns, NPC decisions, and
simulation ticks. Original placeholder graphics live under
`apps/darkorbit_web/priv/static/images/game`; their categories and dimensions
are defined in `assets/js/game/asset_catalog.js`.

## Architecture

See [docs/architecture.md](docs/architecture.md) for application boundaries,
transaction invariants, the audited baseline, and the next implementation
milestone. The longer-term direction is tracked in [ROADMAP.md](ROADMAP.md).


## Experimental stereo cockpit on `sbs`
The `sbs` branch adds optional Three.js 3D cockpit and side-by-side stereo
rendering without changing the authoritative 2D world simulation. Press **V**
to cycle Classic 2D → 3D Cockpit → Stereo SBS. See
[docs/sbs-3d.md](docs/sbs-3d.md) for setup and caveats.


### Navigation Computer V1 (experimental SBS branch)
Press **M** to open the full-sector SVG overview from any flight view.
Click up to eight waypoints, select **Engage autopilot**, then return to
the cockpit with **M** or **Esc**. A server-owned route advances across
simulation ticks; **Stop / cancel course** halts it, and manual steering
overrides the route. See [SBS navigation notes](docs/sbs-3d.md).
