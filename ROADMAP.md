# 🚀 Darkorbit Umbrella – Roadmap

## 🎯 Vision
based on https://github.com/yusufsahinhamza/darkorbit-cms
Rebuild a modern, scalable DarkOrbit server ecosystem using Elixir/OTP, replacing legacy PHP CMS-style architectures with:

- Strong domain modeling
- Real-time systems (Phoenix / Channels)
- Deterministic gameplay state
- Atomic economy + equipment systems
- Clean separation of concerns (umbrella apps)

Inspired by:
- Legacy CMS implementations (PHP-based control panels, game logic coupling)
- Private server ecosystems (equipment, PvP, progression loops)
- Goal: production-grade MMO backend

---

## 🧠 Current Architecture (What We Have)

### Core Domains Implemented

#### ✅ Accounts
- Registration
- Session generation
- Player metadata (credits, uridium, level, etc.)

#### ✅ Inventory System
- Persistent player_equipment
- Structured equipment bag:
  - lasers
  - generators
  - drones (future-ready)
- Helpers:
  - laser_count/2
  - add_lasers/3
  - remove_laser/3

#### ✅ Fleet (Ships)
- player_ships per user
- Ownership validation
- Active ship switching
- Starter ship provisioning

#### ✅ Loadouts (Critical System)
- 2 configs per ship
- Slot-based system:
  - ship slots
  - drone slots
- Fixed slot arrays (deterministic layout)

#### ✅ Equipment Engine (Major Milestone)
- Equip / unequip
- Slot validation:
  - bounds
  - capacity (ship-specific)
- Inventory integration:
  - consume on equip
  - return on overwrite
- Atomic transactions via Ecto.Multi

#### ✅ Preferences / Titles
- Player settings
- Titles ownership + selection

---

## ✅ Completed Milestones

### Milestone A — Persistent player domains

- Account registration and authentication
- Inventory, fleet, two ship configurations, preferences, and titles
- Slot-based equipment mutations and starter-ship provisioning

### Milestone B — Persistent-state hardening

- Atomic account provisioning and equipment replacement
- Ownership-scoped mutations, row locks, uniqueness constraints, and database checks
- Concurrent inventory and loadout regression coverage

### Milestone C — Derived stats and authoritative world

- Configurable ship and equipment catalogs
- Pure configuration-aware ship-stat calculation
- Supervised sector `1-1`, sessions, bounded server-owned movement, deterministic ticks, and PubSub events

### Milestone D — Authenticated browser flight

- Credential login, signed game socket tokens, and an authenticated Phoenix world channel
- Canvas 2D sector renderer, original placeholder graphics, interpolated authoritative snapshots, and multiplayer movement events
- Playable development pilots seeded for browser testing

### Milestone D.1 — Continuous mouse navigation

- Single-click destination setting remains available
- Click-and-hold continuously steers toward the pointer at approximately 10 commands per second
- Pointer destinations are recalculated as the camera follows the ship
- Pointer capture, cancellation, focus loss, and hidden-tab cleanup are handled safely
- Near-ship and redundant retargets are suppressed to avoid jitter and unnecessary traffic
- The client still sends destination intent only; boundary validation, position, and speed remain server-owned

### Milestone E — Server-authoritative NPC combat

- Configurable original NPC catalog with three deterministic `Rift Skirmisher` spawns in sector `1-1`
- Map-owned NPC movement, hull, shields, targeting, bounded AI, destruction, and tick-based respawning
- Pure range, cooldown, shield-absorption, hull-damage, and destruction rules
- Authenticated target/select/fire channel intentions with authoritative multiplayer combat events
- Right-click and accessible nearest-target selection, target HUD, Space/click firing, laser and hit effects, and explosions
- Catalog-defined Phoenix pulse emitter so existing development pilots can fight without inventory grants or duplication

Graphical ship flight and continuous mouse navigation have been manually verified. Two-player browser synchronization and the complete Milestone E browser combat encounter are implemented and covered by automated tests, but await manual verification in browser sessions.

---

## 🚧 Next Major Milestones

### 1. Inventory Expansion
- Drone equipment slots
- Ammo system
- Stackable vs unique items

### 2. Ship Stats Engine ✅
- Configurable ship and equipment catalogs
- Two configuration-aware loadouts
- Pure derived stats from equipped inventory

### 3. Combat System (initial PvE slice complete)
- Server-authoritative NPC targeting, damage, cooldowns, destruction, and respawning ✅
- Server-authoritative NPC attacks and player damage ✅
- PvP, ammunition, rewards, and player respawning remain future work

### 4. Map / World Layer (initial player-flight slice complete)
- Supervised starting map (1-1)
- Server-owned player positioning and bounded movement
- Configurable deterministic simulation ticks
- Continuous click-and-hold client navigation ✅
- NPC spawning, AI, combat, destruction, and respawning ✅

### 5. Real-Time Layer (movement and PvE slices complete)
- Authenticated Channels and sockets ✅
- Connected-player presence and disconnect cleanup ✅
- Movement synchronization ✅
- Targeting, laser, damage, destruction, and respawn events ✅

### 6. Economy System
- Shop / purchases
- Credits vs Uridium balancing
- Loot drops
- Auction system

### 7. Progression Systems
- Experience → leveling
- Rank system
- Skill tree
- Drone leveling

### 8. CMS Replacement Layer
- Phoenix LiveView dashboard
- API-first backend
- Real-time updates

---

## 🧱 Architectural Direction

Principles:
- Persistent account state is authoritative in the database
- Live movement and combat state is authoritative in map processes
- Derived values are computed, never stored
- All mutations are transactional
- Systems are composable

---

## ⚠️ Known Gaps

- Two-player browser synchronization and the Milestone E combat encounter await manual browser verification
- Destroyed player recovery, ammunition, loot, rewards, and PvP are not implemented
- Live map state is ephemeral, single-node, and has no crash recovery or spatial partitioning
- Initial map, NPC, and combat balance values remain provisional
- No anti-cheat layer

---

## ✅ Immediate Next Task

Manually exercise the complete combat acceptance flow in two browser sessions,
then design player recovery and reward handling without moving combat authority
out of `Core.World.MapServer`.
