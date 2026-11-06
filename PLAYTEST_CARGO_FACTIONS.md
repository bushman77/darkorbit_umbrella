# Space Nova — Merchant Cargo and Faction Playtest

Branch: `sbs`. This is a manual acceptance checklist for the first
server-authoritative combat → surrender → cargo → reputation slice.

## Automated integration

Run from the umbrella root after installing dependencies and applying migrations:

```sh
git status --short
git pull --ff-only origin sbs
mix ecto.migrate
mix test apps/darkorbit_web/test/darkorbit_web/channels/world_channel_test.exs
mix test
```

The channel test file covers a seeded neutral Harbor Scow with **a genuine
MapServer laser hit**, a server-owned surrender transition, and:
- cargo seizure, account hold persistence, SOL vessel manifest debit,
  one attack penalty plus one seizure penalty, and replay rejection;
- release without taking cargo (attack penalty only);
- full-hold rejection with no cargo or seizure penalty and a permitted release.

The deterministic test fixture starts the Scow just above the surrender
threshold. It does *not* forge surrender or skip the real weapon and
map-verified settlement paths.

## Live cockpit and SBS check

1. Start with room in the Sunracer hold; check `/equipment` for capacity,
   the current cargo manifest and existing SOL faction standings. Those
   standings persist between sessions and might not begin at 0.
2. In Atlas, set a course that encounters neutral merchant traffic. Hail
   the vessel to note its faction and manifest; then choose **Attack vessel**.
3. Land one actual laser hit. The laptop should report a faction hit of
   **−12** for that merchant's faction, **once** per physical vessel/voyage.
4. Continue until the Scow surrenders. The paired phone SBS should show the
   surrender notice directly in its stereo HUD.
5. Choose **Seize cargo** on the laptop. The hold receives only catalog-known
   items that fit its capacity. A civilian seizure costs a further **−18**
   faction standing. The SOL vessel retains any unclaimed manifest units.
6. Check `/equipment` again: cargo hold, standing and receipt history must
   agree with the encounter. A neutral pilot starting at 0 and performing one
   attack plus one seizure should be at **−30** for that faction.
7. Try replaying the prior encounter command, or rejoining and attempting the
   same vessel/voyage. It must never award another copy of the cargo.
8. Repeat with a full hold. Seizure must fail safely and **Release captain**
   must still resolve the encounter. A release without seizure does not
   create a cargo receipt or impose the additional −18 standing penalty.

## Expected crate conversion

V1 maps **ten abstract strategic manifest units to one 1-tonne crate**.
For example, an unmodified Harbor trader carries 32 industrial-parts units;
an empty four-tonne Sunracer can seize 3 crates (3 tonnes), leaving 2
strategic units aboard that merchant.

Cargo contents and faction names differ for other merchant routes, and a
previously loaded hold limits the amount credited.

## Not yet in this milestone

- Planetary market buy/sell and commodity pricing
- Durable SOL traffic and in-flight settlement recovery after an OTP restart
- A shared map-level infraction broadcaster for damage with no owner channel

Do not use the absence of a live-event notification as proof that a DB
transaction has succeeded. Verify actual inventory and standings in
`/equipment`. This playtest must be performed against a running game;
committed regression tests are not a substitute for it.
