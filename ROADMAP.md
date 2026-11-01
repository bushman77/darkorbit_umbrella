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

### Milestone E.1 — Classic combat controls and action hotbar

- Left-click NPC selection uses rendered entity dimensions and consumes the pointer gesture before navigation; empty-space click-and-hold flight is preserved
- Selected and engaged targets are separate authoritative states, with explicit engage/disengage commands and idempotent repeated activation
- The map tick automatically fires the server-defined pulse emitter when range and cooldown rules permit, pauses while out of range, and clears combat across destruction, removal, disconnect, and respawn lifecycles
- Engaged player ships visually face their replicated target independently of movement, then smoothly return to navigation facing when combat ends
- Responsive bottom-center slots `1` through `0` use server-defined action data, with the pulse emitter in slot 1 and safe empty placeholders in slots 2 through 0
- Space, number-row keys, click activation, Esc cancellation, active/selected/empty/cooldown states, and input-control/key-repeat guards are implemented

Manual browser verification confirmed navigation, NPC targeting, persistent laser engagement, combat facing, and circular combat maneuvering for Milestone E.1. Broader multiplayer browser validation remains deferred.

### Milestone E.2.1 — Modular cockpit HUD and persistent layouts

- Ship status, target information, and the minimap now use one reusable cockpit-window system with unique identifiers, dedicated drag handles, focus ordering, collapse controls, and a window visibility menu
- Unlock/lock editing, Pointer Events with capture cleanup, keyboard positioning, viewport clamping, reset-to-default behavior, and versioned per-player browser persistence are implemented without changing authoritative simulation behavior
- The previous main-canvas minimap was replaced by one dedicated, resize-aware minimap canvas driven by the existing interpolated world entities and authoritative map boundaries
- The ten-slot action hotbar remains anchored at bottom center, outside the movable window layer, with its existing click, number-row, Space, Esc, and cooldown behavior preserved
- Narrow viewports use a horizontally scrollable cockpit dock instead of free-floating windows, keeping panels recoverable after resize
- Automated coverage exercises drag lock state, collapse, visibility, reset, persistence, malformed storage, clamping, resize mode, pointer cleanup/input isolation, keyboard behavior, reduced motion, and minimap projection/lifecycle

The E.2.1 code and automated verification are complete. Manual browser verification of the new cockpit at the target viewport sizes has not yet been performed.

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
- Persistent tick-owned player combat engagement and independent combat facing ✅
- Modular local cockpit layout and standalone minimap rendering ✅

### 5. Real-Time Layer (movement and PvE slices complete)
- Authenticated Channels and sockets ✅
- Connected-player presence and disconnect cleanup ✅
- Movement synchronization ✅
- Targeting, laser, damage, destruction, and respawn events ✅
- Engagement, disengagement, hotbar activation, and replicated combat-facing state ✅

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

- The E.2.1 cockpit still requires manual browser verification at 1366×768, 1920×1080, 2560×1440, and mobile-sized viewports
- Two-player synchronization and broader multiplayer browser validation remain deferred
- The minimap is display-only; interactive minimap navigation is planned for Milestone E.2.2
- Destroyed player recovery, ammunition, loot, rewards, and PvP are not implemented
- Live map state is ephemeral, single-node, and has no crash recovery or spatial partitioning
- Initial map, NPC, and combat balance values remain provisional
- No anti-cheat layer

---

## ✅ Immediate Next Task

Manually verify the complete E.2.1 cockpit acceptance flow at the supported
viewport sizes, then implement Milestone E.2.2 interactive minimap navigation
without moving movement authority out of `Core.World.MapServer`. Multiplayer
expansion and broader two-browser validation remain deferred.
