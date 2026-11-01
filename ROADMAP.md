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

## 📊 Current Progress

| System | Status | Completion |
|--------|--------|------------|
| Accounts | Stable | 90% |
| Inventory | Catalog-backed | 90% |
| Fleet | Catalog-backed | 85% |
| Loadouts | Two configs + stats | 95% |
| Equipment Engine | Core Complete | 95% |
| Preferences | Basic | 50% |
| Titles | Basic | 50% |
| Web Layer | Scaffolded | 30% |
| Game Logic | Stats + movement | 40% |
| World Simulation | Starting map | 35% |
| Real-time Systems | PubSub events | 20% |

### Overall Project Progress: ~55%

---

## 🔥 What We Just Achieved

We now have a true MMO-grade equipment pipeline:

Inventory → Loadout → Database (atomic consistency)

Properties:
- No duplication
- No desync
- No ghost items
- Fully deterministic

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

### 3. Combat System
- Targeting system
- Damage calculation
- Cooldowns
- PvP + PvE hooks

### 4. Map / World Layer (initial slice complete)
- Supervised starting map (1-1)
- Server-owned player positioning and bounded movement
- Configurable deterministic simulation ticks
- NPC spawning

### 5. Real-Time Layer (PubSub foundation complete)
- Channels / sockets
- Player presence
- Combat events
- Movement sync

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
- State is authoritative in DB
- Derived values are computed, never stored
- All mutations are transactional
- Systems are composable

---

## ⚠️ Known Gaps

- No combat loop
- No client-facing Channel/socket protocol
- No UI integration
- No anti-cheat layer

---

## ✅ Immediate Next Task

Build the first combat slice and client-facing world protocol on top of the
authoritative simulation.
