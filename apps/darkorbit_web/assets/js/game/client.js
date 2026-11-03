import {Socket} from "phoenix"
import {
  applyAuthoritativeDamage,
  entityKey,
  healthPercent,
  nearestNpc,
} from "./combat_client.mjs"
import {
  combatKeyIntent,
  gameplayTypingTarget,
  manualLaserPointerIntent,
  desiredEntityAngle,
  hotbarActionActive,
  smoothAngle,
} from "./combat_controls.mjs"
import {CockpitWindowManager} from "./cockpit_window_manager.mjs"
import {MinimapRenderer} from "./minimap_renderer.mjs"
import {PointerNavigation} from "./pointer_navigation.mjs"
import {StereoSpaceView} from "./stereo_view.js"
import {HelmetControl} from "./helmet_control.mjs"
import {helmetAlignmentKeyIntent} from "./helmet_alignment_keys.mjs"
import {NavigationComputer} from "./navigation_computer.mjs"
import {FlightControls} from "./flight_controls.mjs"
import {smoothAttitude} from "./attitude_interpolation.mjs"
import {smoothOrientation, orientationTelemetry} from "./orientation_interpolation.mjs"
import {SpaceLaserTrigger} from "./space_laser_trigger.mjs"
import {applyLaserBurstDamage, visualLaserRays} from "./laser_burst.mjs"
import {laserFeedback, LASER_FEEDBACK_MS} from "./laser_feedback.mjs"
import {nextFlightMode, validFlightMode} from "./display_modes.mjs"

const clamp = (value, minimum, maximum) => Math.min(Math.max(value, minimum), maximum)
const validDestination = (destination, boundaries) =>
  destination &&
  Number.isFinite(destination.x) &&
  Number.isFinite(destination.y) &&
  destination.x >= 0 &&
  destination.x <= boundaries.width &&
  destination.y >= 0 &&
  destination.y <= boundaries.height
const number = value => new Intl.NumberFormat("en-US", {maximumFractionDigits: 0}).format(value || 0)

class SpaceClient {
  constructor(root) {
    this.root = root
    // Transparent DOM hit surface. Three.js owns the only flight renderer.
    this.canvas = root.querySelector("#space-viewport")
    this.stereoView = null
    this.displayMode = "3d"
    this.mapId = root.dataset.mapId
    this.token = root.dataset.socketToken
    this.entities = new Map()
    this.pilots = new Map()
    this.boundaries = {width: 20000, height: 12000}
    this.volume = {altitude_min: -3000, altitude_max: 3000}
    this.selfId = null
    this.player = null
    this.commandDestination = null
    this.selectedTargetId = null
    this.selectedHotbarSlot = 1
    this.worldTick = 0
    this.tickMs = 100
    this.beams = []
    this.lastLaserFeedback = null
    this.lastFrame = performance.now()
  }

  inSystemCruise() {
    return this.navComputer?.solarNavigation?.status === "traveling"
  }

  start() {
    if (!this.canvas || !this.root.querySelector("#space-viewport-3d")) {
      this.showError("The 3D flight viewport is missing.")
      return
    }

    this.cockpit = new CockpitWindowManager({
      root: this.root.querySelector("#cockpit-interface"),
      playerId: this.root.dataset.layoutPlayerId,
    }).start()
    this.minimap = new MinimapRenderer({
      canvas: this.root.querySelector("#cockpit-minimap-canvas"),
      getEntities: () => this.entities.values(),
      getBoundaries: () => this.boundaries,
      getSelfId: () => this.selfId,
      getDestination: () => this.commandDestination,
    }).start()
    this.flightControls = new FlightControls({
      active: () => !this.navComputer?.isOpen && !this.inSystemCruise() &&
        this.channel?.state === "joined" &&
        this.entities.get(this.selfId)?.status !== "destroyed",
      send: input => this.sendFlightControls(input),
    })
    window.addEventListener("keydown", event => this.flightControls.keyDown(event))
    window.addEventListener("keyup", event => this.flightControls.keyUp(event))
    // Only the cockpit hit canvas owns flight input; menus/Atlas retain
    // ordinary scrolling and right-click behavior.
    this.canvas.addEventListener("wheel", event => this.flightControls.wheel(event),
      {passive: false})
    window.addEventListener("blur", () => {
      this.flightControls.release()
      this.spaceLaser?.release()
    })
    document.addEventListener("visibilitychange", () => {
      if (document.hidden) {
        this.flightControls.release()
        this.spaceLaser?.release()
      }
    })
    this.navComputer = new NavigationComputer({
      root: this.root.querySelector("#navigation-computer"),
      getEntities: () => this.entities,
      getSelfId: () => this.selfId,
      getBoundaries: () => ({...this.boundaries, ...this.volume}),
      isConnected: () => this.channel?.state === "joined" && Boolean(this.selfId),
      engage: (waypoints, done) => this.plotCourse(waypoints, done),
      halt: done => this.stopNavigation(done),
      solarSetCourse: (bodyId, done) => this.solarSetCourse(bodyId, done),
      solarCancelCourse: done => this.solarCancelCourse(done),
      onOpen: () => {
        this.helmet?.setCombat(false)
        this.navigation?.cancel()
        this.flightControls.release({silent: true})
        this.spaceLaser?.release()
      },
      onClose: () => {
        this.helmet?.closePanel()
        this.helmet?.setCombat(true)
        this.canvas.focus({preventScroll: true})
      },
    }).start()
    this.root.querySelector("#nav-open")?.addEventListener("click", () => this.navComputer.open())
    window.addEventListener("keydown", event => this.navComputer.handleKey(event))
    this.root.querySelector("#display-mode")?.addEventListener("change", event => this.setDisplayMode(event.target.value))
    window.addEventListener("keydown", event => this.handleDisplayModeKey(event))
    // Capture before ordinary gameplay handlers or browser reload behavior.
    window.addEventListener("keydown", event => this.handleHelmetAlignmentKey(event), true)
    if (!this.setDisplayMode("3d")) return
    this.canvas.addEventListener("pointerdown", () => this.canvas.focus({preventScroll: true}))
    window.addEventListener("resize", () => this.resize())
    this.navigation = new PointerNavigation({
      canvas: this.canvas,
      destinationForPointer: () => null,
      shipPosition: () => this.entities.get(this.selfId)?.target,
      sendDestination: destination => this.sendDestination(destination),
      // In cockpit mode click selects targets; travel is plotted on the atlas.
      interceptPointerDown: pointer => {
        this.selectTargetAtPointer(pointer)
        return true
      },
    }).attach()
    this.canvas.addEventListener("pointerdown", event => this.handleLaserPointerDown(event))
    this.canvas.addEventListener("contextmenu", event => {
      if (!this.navComputer?.isOpen) event.preventDefault()
    })
    this.spaceLaser = new SpaceLaserTrigger({
      active: () => !this.navComputer?.isOpen && !this.inSystemCruise() &&
        this.channel?.state === "joined" &&
        this.entities.get(this.selfId)?.status !== "destroyed",
      worldTick: () => this.worldTick,
      nextAttackTick: () => Number(this.entities.get(this.selfId)?.nextAttackTick) || 0,
      fire: done => this.fireReadyWeapon(done),
    })
    window.addEventListener("pointerup", event => {
      if (event.button === 2) this.spaceLaser.release()
    })
    window.addEventListener("pointercancel", () => this.spaceLaser.release())
    for (const slot of this.root.querySelectorAll("[data-hotbar-slot]")) {
      slot.addEventListener("click", () => this.activateHotbarSlot(Number(slot.dataset.hotbarSlot)))
    }
    window.addEventListener("keydown", event => this.handleCombatKey(event), true)

    // New sessions begin in the SOL system Atlas, not in the combat
    // cockpit. Initialize all flight/weapon input guards first so the
    // Atlas can safely own focus even before the world socket joins.
    // Closing it hands focus back to the existing 3D / SBS cockpit.
    this.navComputer.open()
    this.connect()
    requestAnimationFrame(time => this.frame(time))
  }

  connect() {
    this.socket = new Socket("/socket", {params: {token: this.token}})
    this.socket.onOpen(() => this.setConnection("Relay connected", "online"))
    this.socket.onError(() => this.setConnection("Relay interrupted", "error"))
    this.socket.onClose(() => this.setConnection("Relay offline", "error"))
    this.socket.connect()
    this.helmet = new HelmetControl({
      root: this.root,
      socket: this.socket,
      playerId: this.root.dataset.layoutPlayerId,
      combatActive: !this.navComputer.isOpen,
    }).start()

    this.channel = this.socket.channel(`world:${this.mapId}`, {})
    this.channel.on("world_state", state => this.applyWorldState(state))
    this.channel.on("solar_navigation_updated", payload => {
      if (String(payload.player_id) === String(this.selfId) && payload.navigation) {
        this.applySolarNavigation(payload.navigation)
      }
    })
    this.channel.on("movement_started", entity => this.upsertEntity(entity))
    this.channel.on("entity_joined", entity => this.entityJoined(entity))
    this.channel.on("entity_left", entity => this.removeEntity(entity.id))
    this.channel.on("npc_spawned", entity => this.upsertEntity(entity, true))
    this.channel.on("npc_movement_started", entity => this.upsertEntity(entity))
    this.channel.on("npc_state_changed", entity => this.upsertEntity(entity))
    this.channel.on("target_selected", selection => this.targetSelected(selection))
    this.channel.on("target_cleared", selection => this.targetCleared(selection))
    this.channel.on("combat_engaged", engagement => this.combatEngaged(engagement))
    this.channel.on("combat_disengaged", engagement => this.combatDisengaged(engagement))
    this.channel.on("laser_fired", attack => this.laserFired(attack))
    this.channel.on("entity_destroyed", destruction => this.entityDestroyed(destruction))
    this.channel.onError(() => this.setConnection("Sector channel lost", "error"))
    this.channel.onClose(() => this.setConnection("Sector channel closed", "error"))

    this.channel
      .join()
      .receive("ok", response => this.joined(response))
      .receive("error", response => {
        const reason = response.reason === "already_connected"
          ? "This pilot already has an active sector connection."
          : `Unable to join sector: ${response.reason || "unknown error"}`
        this.showError(reason)
        this.setConnection("Join rejected", "error")
      })
      .receive("timeout", () => {
        this.showError("The sector relay did not answer in time.")
        this.setConnection("Join timeout", "error")
      })
  }

  joined(response) {
    this.player = response.player
    this.selfId = entityKey(response.player.pilot.id)
    this.boundaries = response.map.boundaries
    this.volume = response.map.volume || this.volume
    this.worldTick = response.map.tick
    this.tickMs = response.map.tick_ms
    this.pilots = new Map(Object.entries(response.pilots || {}))

    if(response.solar_navigation)this.applySolarNavigation(response.solar_navigation)
    for (const entity of response.map.entities) this.upsertEntity(entity, true)
    this.syncOwnCombatState()

    this.flightControls.resetThrottle()
    this.flightControls.mode = "cruise"
    this.populateHud()
    this.setConnection("Authoritative sync", "online")
  }

  applyWorldState(state) {
    this.boundaries = state.boundaries || this.boundaries
    this.volume = state.volume || this.volume
    this.worldTick = state.tick
    this.tickMs = state.tick_ms || this.tickMs
    const activeIds = new Set()

    for (const entity of state.entities) {
      activeIds.add(entityKey(entity.id))
      this.upsertEntity(entity)
    }

    for (const id of this.entities.keys()) {
      if (!activeIds.has(id)) this.removeEntity(id)
    }

    this.syncOwnCombatState()
    this.updateCombatHud()
  }

  entityJoined(entity) {
    if (entity.pilot) this.pilots.set(entityKey(entity.player_id), entity.pilot)
    this.upsertEntity(entity)
  }

  upsertEntity(entity, snap = false) {
    const id = entityKey(entity.id)
    const existing = this.entities.get(id)
    const p3 = entity.position_3d || entity.position
    const target = {x: p3.x, y: p3.y, z: p3.z ?? 0}
    const d3 = entity.destination_3d || entity.destination
    const destination = d3 ? {x: d3.x, y: d3.y, z: d3.z ?? 0} : null
    const route3d = entity.route_waypoints_3d || entity.route_waypoints || []
    const attitude = entity.attitude || {yaw: 0, pitch: 0, roll: 0}
    const orientation = entity.orientation || null
    const velocity = entity.velocity || {x: 0, y: 0, z: 0}

    if (existing) {
      existing.target = target
      existing.destination = destination
      existing.navigationMode = entity.navigation_mode || "manual"
      existing.routeWaypoints = route3d
      existing.attitude = attitude
      existing.orientation = orientation
      if (orientation && (!existing.renderOrientation || snap)) {
        existing.renderOrientation = {...orientation}
      }
      // Render orientation is independent from server state; never feed the
      // interpolated angles back into the authoritative simulation.
      if (!existing.renderAttitude || snap) existing.renderAttitude = {...attitude}
      existing.angularVelocity = entity.angular_velocity || existing.angularVelocity ||
        {yaw: 0, pitch: 0, roll: 0}
      existing.velocity = velocity
      existing.throttle = entity.throttle ?? 0
      existing.flightMode = entity.flight_mode || "cruise"
      existing.speed = entity.speed
      existing.kind = entity.kind || existing.kind
      existing.playerId = entity.player_id == null ? existing.playerId : entityKey(entity.player_id)
      existing.npcTypeId = entity.npc_type_id || existing.npcTypeId
      existing.displayName = entity.display_name || existing.displayName
      existing.hull = entity.hull
      existing.maxHull = entity.max_hull
      existing.shields = entity.shields
      existing.maxShields = entity.max_shields
      existing.shieldAbsorption = entity.shield_absorption
      existing.damage = entity.damage
      existing.attackRange = entity.attack_range
      existing.attackCooldownTicks = entity.attack_cooldown_ticks
      existing.nextAttackTick = entity.next_attack_tick
      existing.targetId = entity.target_id == null ? null : entityKey(entity.target_id)
      existing.engagedTargetId = entity.engaged_target_id == null
        ? null
        : entityKey(entity.engaged_target_id)
      existing.state = entity.state
      existing.status = entity.status
      if (destination) {
        existing.navigationAngle = Math.atan2(
          destination.y - existing.render.y,
          destination.x - existing.render.x
        )
      }
      if (snap) existing.render = {...target}
    } else {
      this.entities.set(id, {
        id,
        kind: entity.kind || "player",
        playerId: entity.player_id == null ? null : entityKey(entity.player_id),
        npcTypeId: entity.npc_type_id,
        displayName: entity.display_name,
        render: {...target},
        target,
        destination,
        navigationMode: entity.navigation_mode || "manual",
        routeWaypoints: route3d,
        attitude,
        renderAttitude: {...attitude},
        orientation,
        renderOrientation: orientation ? {...orientation} : null,
        angularVelocity: entity.angular_velocity || {yaw: 0, pitch: 0, roll: 0},
        velocity,
        throttle: entity.throttle ?? 0,
        flightMode: entity.flight_mode || "cruise",
        speed: entity.speed,
        hull: entity.hull,
        maxHull: entity.max_hull,
        shields: entity.shields,
        maxShields: entity.max_shields,
        shieldAbsorption: entity.shield_absorption,
        damage: entity.damage,
        attackRange: entity.attack_range,
        attackCooldownTicks: entity.attack_cooldown_ticks,
        nextAttackTick: entity.next_attack_tick,
        targetId: entity.target_id == null ? null : entityKey(entity.target_id),
        engagedTargetId: entity.engaged_target_id == null
          ? null
          : entityKey(entity.engaged_target_id),
        state: entity.state,
        status: entity.status,
        navigationAngle: destination
          ? Math.atan2(destination.y - target.y, destination.x - target.x)
          : -Math.PI / 2,
        angle: destination
          ? Math.atan2(destination.y - target.y, destination.x - target.x)
          : -Math.PI / 2,
      })
    }

    if (id === this.selfId) {
      this.commandDestination = entity.status !== "destroyed" && validDestination(destination, this.boundaries)
        ? {...destination}
        : null
      this.updateNavigationStatus()
    }
  }

  sendFlightControls(input) {
    if (this.channel?.state !== "joined") return
    this.channel.push("flight_controls", input, 3000)
      .receive("ok", response => {
        if (response.entity) this.upsertEntity(response.entity)
      })
      .receive("error", response => this.showError(`Flight controls rejected: ${response.reason}`))
      .receive("timeout", () => this.showError("Flight control link timed out."))
  }

  applySolarNavigation(navigation) {
    this.navComputer.setSolarNavigation(navigation)
    const active=this.inSystemCruise()
    this.root.dataset.propulsionMode=active?"interplanetary_cruise":"conventional"
    const label=this.root.querySelector("#propulsion-status")
    if(label)label.textContent=active?"SUBLIGHT CRUISE / FLIGHT LOCKED":"CONVENTIONAL FLIGHT"
    if(active){
      this.flightControls?.release({silent:true})
      this.spaceLaser?.release()
      this.navigation?.cancel()
    }
  }

  solarSetCourse(bodyId, done) {
    if(this.channel?.state!=="joined")return done(false,null,"relay offline")
    this.channel.push("solar_set_course",{body_id:bodyId},5000)
      .receive("ok",response=>done(true,response.navigation))
      .receive("error",response=>done(false,null,response.reason))
      .receive("timeout",()=>done(false,null,"timeout"))
  }

  solarCancelCourse(done) {
    if(this.channel?.state!=="joined")return done(false,null,"relay offline")
    this.channel.push("solar_cancel_course",{},5000)
      .receive("ok",response=>done(true,response.navigation))
      .receive("error",response=>done(false,null,response.reason))
      .receive("timeout",()=>done(false,null,"timeout"))
  }

  plotCourse(waypoints, done) {
    if (this.channel?.state !== "joined") return done(false, "relay offline")
    this.channel.push("plot_course", {waypoints}, 5000)
      .receive("ok", response => {
        if (response.entity) this.upsertEntity(response.entity)
        this.flightControls.resetThrottle()
        done(true)
      })
      .receive("error", response => done(false, response.reason))
      .receive("timeout", () => done(false, "timeout"))
  }

  stopNavigation(done) {
    if (this.channel?.state !== "joined") return done(false, "relay offline")
    this.channel.push("stop_navigation", {}, 5000)
      .receive("ok", response => {
        if (response.entity) this.upsertEntity(response.entity)
        done(true)
      })
      .receive("error", response => done(false, response.reason))
      .receive("timeout", () => done(false, "timeout"))
  }

  sendDestination(destination) {
    if (this.inSystemCruise()) return false
    if (!validDestination(destination, this.boundaries)) return false
    if (!this.channel || !this.selfId || this.channel.state !== "joined") {
      this.showError("Navigation is unavailable while the sector relay reconnects.")
      return false
    }

    this.channel
      .push("move", destination, 5000)
      .receive("ok", response => {
        if (response.entity) this.upsertEntity(response.entity)
      })
      .receive("error", response => {
        this.showError(`Navigation rejected: ${response.reason}`)
        this.updateNavigationStatus()
      })
      .receive("timeout", () => this.showError("Navigation command timed out."))

    return true
  }

  handleLaserPointerDown(event) {
    const active = !this.navComputer?.isOpen && !this.inSystemCruise() &&
      this.channel?.state === "joined" &&
      this.entities.get(this.selfId)?.status !== "destroyed"
    if (!manualLaserPointerIntent(event, active)) return

    event.preventDefault()
    this.canvas.focus({preventScroll: true})
    this.spaceLaser?.press()
  }

  selectTargetAtPointer(pointer) {
    if (this.inSystemCruise()) return false
    const rect = this.canvas.getBoundingClientRect()
    const targetId = this.stereoView?.selectNpc(pointer, rect)
    if (!targetId) return false
    this.selectTarget(targetId)
    return true
  }

  handleCombatKey(event) {
    if (this.navComputer?.isOpen) return
    if (this.inSystemCruise()) return
    if (event.defaultPrevented) return
    const intent = combatKeyIntent(event)
    if (!intent) return

    event.preventDefault()
    if (intent.type === "toggle_laser") this.toggleLaserFire()
    if (intent.type === "disengage") this.disengageCombat()
    if (intent.type === "activate_slot") this.activateHotbarSlot(intent.slot)
    if (intent.type === "target_nearest") this.selectNearestTarget()
  }

  selectNearestTarget() {
    const ownShip = this.entities.get(this.selfId)
    const target = nearestNpc(this.entities.values(), ownShip?.target)
    if (target) this.selectTarget(target.id)
    else this.setCombatMessage("No hostile signal in sector telemetry.")
  }

  selectTarget(targetId) {
    if (this.inSystemCruise()) return
    if (!this.channel || !this.selfId) return

    this.channel
      .push("select_target", {target_id: targetId}, 5000)
      .receive("ok", response => this.targetSelected(response.selection))
      .receive("error", response => this.setCombatMessage(`Target rejected: ${response.reason}`))
      .receive("timeout", () => this.setCombatMessage("Targeting command timed out."))
  }

  disengageCombat() {
    if (!this.channel || !this.selfId) return

    this.channel
      .push("disengage_combat", {}, 5000)
      .receive("ok", engagement => {
        this.combatDisengaged(engagement)
        this.targetCleared(engagement)
      })
      .receive("error", response => this.setCombatMessage(`Disengage rejected: ${response.reason}`))
  }

  engageCombat() {
    if (!this.channel || !this.selfId) return
    if (!this.selectedTargetId) {
      this.setCombatMessage("Select an NPC before engaging.")
      return
    }

    this.channel
      .push("engage_combat", {}, 5000)
      .receive("ok", engagement => this.combatEngaged(engagement))
      .receive("error", response => this.setCombatMessage(this.attackError(response.reason)))
      .receive("timeout", () => this.setCombatMessage("Engagement command timed out."))
  }

  fireReadyWeapon(done) {
    if (this.channel?.state !== "joined" || !this.selfId) {
      done(false, "disconnected")
      return
    }

    this.channel
      .push("fire_ready_weapon", {}, 3000)
      .receive("ok", shot => {
        const own = this.entities.get(this.selfId)
        if (own) own.nextAttackTick = shot.next_attack_tick
        this.worldTick = Math.max(this.worldTick, Number(shot.tick) || 0)
        done(true)
      })
      .receive("error", response => {
        this.setCombatMessage(this.attackError(response.reason))
        done(false, response.reason)
      })
      .receive("timeout", () => {
        this.setCombatMessage("Manual laser command timed out.")
        done(false, "timeout")
      })
  }

  toggleLaserFire() {
    if (!this.channel || !this.selfId) return

    this.channel
      .push("toggle_laser_fire", {}, 5000)
      .receive("ok", engagement => this.applyLaserToggle(engagement))
      .receive("error", response => this.setCombatMessage(this.attackError(response.reason)))
      .receive("timeout", () => this.setCombatMessage("Laser toggle timed out."))
  }

  activateHotbarSlot(slot) {
    if (this.inSystemCruise()) return
    if (!this.channel || !this.selfId || !Number.isInteger(slot)) return

    this.selectedHotbarSlot = slot
    this.updateHotbar()
    this.channel
      .push("activate_action", {slot}, 5000)
      .receive("ok", activation => {
        if (activation.status === "empty") {
          this.setCombatMessage(`Action slot ${slot === 10 ? 0 : slot} is empty.`)
        } else if (activation.engagement) this.applyLaserToggle(activation.engagement)
      })
      .receive("error", response => this.setCombatMessage(this.attackError(response.reason)))
      .receive("timeout", () => this.setCombatMessage("Action activation timed out."))
  }

  targetSelected(selection) {
    if (entityKey(selection.player_id) !== this.selfId) return
    this.selectedTargetId = entityKey(selection.target_id)
    const ownShip = this.entities.get(this.selfId)
    if (ownShip) ownShip.targetId = this.selectedTargetId
    this.setCombatMessage("Target lock confirmed.")
    this.updateCombatHud()
  }

  targetCleared(selection) {
    if (entityKey(selection.player_id) !== this.selfId) return
    this.selectedTargetId = null
    const ownShip = this.entities.get(this.selfId)
    if (ownShip) {
      ownShip.targetId = null
      ownShip.engagedTargetId = null
    }
    this.setCombatMessage("Target lock cleared.")
    this.updateCombatHud()
  }

  combatEngaged(engagement) {
    const player = this.entities.get(entityKey(engagement.player_id))
    if (player) player.engagedTargetId = entityKey(engagement.target_id)
    if (entityKey(engagement.player_id) !== this.selfId) return

    this.selectedTargetId = entityKey(engagement.target_id)
    this.selectHotbarAction(engagement.action_id)
    this.setCombatMessage("X1 laser automatic fire engaged.")
    this.updateCombatHud()
  }

  combatDisengaged(engagement) {
    const player = this.entities.get(entityKey(engagement.player_id))
    if (player) player.engagedTargetId = null
    if (entityKey(engagement.player_id) !== this.selfId) return

    this.setCombatMessage(
      engagement.reason === "laser_toggled_off"
        ? "Laser fire stopped. Target lock retained."
        : "Combat disengaged."
    )
    this.updateCombatHud()
  }

  applyLaserToggle(engagement) {
    if (engagement.active) this.combatEngaged(engagement)
    else this.combatDisengaged(engagement)
  }

  selectHotbarAction(actionId) {
    if (!actionId) return

    const slot = [...this.root.querySelectorAll("[data-hotbar-slot]")]
      .find(element => element.dataset.actionId === String(actionId))

    if (slot) this.selectedHotbarSlot = Number(slot.dataset.hotbarSlot)
  }

  syncOwnCombatState() {
    const ownShip = this.entities.get(this.selfId)
    if (!ownShip) return
    this.selectedTargetId = ownShip.targetId
  }

  laserFired(attack) {
    const attacker = this.entities.get(entityKey(attack.attacker_id))
    const target = this.entities.get(entityKey(attack.target_id))
    applyLaserBurstDamage(this.entities, attack)
    if (attacker) attacker.nextAttackTick = attack.next_attack_tick
    this.worldTick = Math.max(this.worldTick, Number(attack.tick) || 0)

    const startedAt = performance.now()
    for (const ray of visualLaserRays(attack, attacker, target)) {
      this.beams.push({
        ...ray,
        hostile: attacker?.kind === "npc",
        shooterId: entityKey(attack.attacker_id),
        startedAt,
        expiresAt: startedAt + 550,
      })
    }

    if (entityKey(attack.attacker_id) === this.selfId) {
      this.lastLaserFeedback = laserFeedback(attack, this.entities, startedAt)
      const feedback = this.lastLaserFeedback
      this.setCombatMessage(feedback.label + "  " + feedback.detail)
    }

    this.updateCombatHud()
  }

  entityDestroyed(destruction) {
    const id = entityKey(destruction.entity.id)
    const entity = this.entities.get(id)
    if (destruction.entity.kind === "npc") this.removeEntity(id)
    if (this.selectedTargetId === id) this.selectedTargetId = null

    this.setCombatMessage(
      destruction.entity.kind === "npc" ? "Hostile destroyed. Respawn telemetry queued." : "Ship destroyed."
    )
    this.updateCombatHud()
  }

  removeEntity(id) {
    const key = entityKey(id)
    this.entities.delete(key)
    if (this.selectedTargetId === key) this.selectedTargetId = null
    for (const entity of this.entities.values()) {
      if (entity.targetId === key) entity.targetId = null
      if (entity.engagedTargetId === key) entity.engagedTargetId = null
    }
  }

  attackError(reason) {
    const messages = {
      no_target: "Select an NPC before engaging.",
      target_not_found: "The selected target is no longer active.",
      out_of_range: "Target is outside laser range. Navigate closer.",
      weapon_cooldown: "Laser is recharging.",
      attacker_destroyed: "Destroyed ships cannot fire.",
      weapon_unarmed: "No server-authorized weapon is available.",
    }
    return messages[reason] || `Laser rejected: ${reason}`
  }

  frame(time) {
    const deltaSeconds = Math.min((time - this.lastFrame) / 1000, 0.1)
    this.lastFrame = time
    this.interpolate(deltaSeconds)
    this.flightControls?.heartbeat(time)
    this.spaceLaser?.update(time)
    this.draw(time)
    this.minimap?.draw(time)
    this.navComputer?.draw(time)
    this.updateCoordinates()
    this.updateCombatHud()
    requestAnimationFrame(nextTime => this.frame(nextTime))
  }

  interpolate(deltaSeconds) {
    const positionBlend = 1 - Math.exp(-deltaSeconds / 0.085)

    for (const entity of this.entities.values()) {
      entity.render.x += (entity.target.x - entity.render.x) * positionBlend
      entity.render.y += (entity.target.y - entity.render.y) * positionBlend
      entity.render.z = (entity.render.z ?? 0) +
        ((entity.target.z ?? 0) - (entity.render.z ?? 0)) * positionBlend
      if (entity.attitude) {
        entity.renderAttitude = smoothAttitude(
          entity.renderAttitude || entity.attitude,
          entity.attitude,
          deltaSeconds
        )
      }
      if (entity.orientation) {
        entity.renderOrientation = smoothOrientation(
          entity.renderOrientation || entity.orientation,
          entity.orientation, deltaSeconds
        )
      }
    }

    const rotationBlend = 1 - Math.exp(-deltaSeconds / 0.075)
    for (const entity of this.entities.values()) {
      entity.angle = smoothAngle(
        entity.angle,
        desiredEntityAngle(entity, this.entities),
        rotationBlend
      )
    }

  }

  draw(time) {
    // A missing WebGL renderer must never silently bring back Classic 2D.
    if (!this.stereoView) return

    this.stereoView.render(this, time)
    this.beams = this.beams.filter(beam => beam.expiresAt > time)
    const feedback = this.lastLaserFeedback
    const element = this.root.querySelector("#laser-hit-confirmation")
    if (element) {
      const active = feedback && time - feedback.at < LASER_FEEDBACK_MS
      element.classList.toggle("hidden", !active)
      if (active) {
        element.textContent = feedback.label
        element.classList.toggle("text-emerald-200", feedback.hit)
        element.classList.toggle("text-rose-200", !feedback.hit)
        element.classList.toggle("border-emerald-400/50", feedback.hit)
        element.classList.toggle("border-rose-400/50", !feedback.hit)
      }
    }
  }

  populateHud() {
    const {pilot, ship, stats, configuration} = this.player
    this.text("#hud-pilot", pilot.pilot_name)
    this.text("#hud-ship", `${ship.name} · Pilot #${pilot.id}`)
    this.text("#hud-config", `C-${configuration.number}`)
    this.text("#hud-hp", `${number(stats.hit_points)} / ${number(stats.hit_points)}`)
    this.text("#hud-shields", `${number(stats.shields)} / ${number(stats.shields)}`)
    this.text("#hud-compact-hp", number(stats.hit_points))
    this.text("#hud-compact-shields", number(stats.shields))
    this.text("#hud-speed", `${number(stats.speed)} u/s`)
    this.root.querySelector("#hud-hp-bar").style.width = "100%"
    this.root.querySelector("#hud-shield-bar").style.width = stats.shields > 0 ? "100%" : "0%"

    const equipment = [...configuration.lasers, ...configuration.generators, ...configuration.drones]
    this.text(
      "#hud-equipment",
      equipment.length ? equipment.map(item => item.name).join(" · ") : "Phoenix pulse emitter · Base ship systems"
    )
  }

  updateCoordinates() {
    const ownShip = this.entities.get(this.selfId)
    if (!ownShip) return
    this.text("#hud-coordinates", `${number(ownShip.render.x)} / ${number(ownShip.render.y)} / ${number(ownShip.render.z)}`)
    this.text("#hud-flight-mode", (ownShip.flightMode || "cruise").toUpperCase())
    this.text("#hud-throttle", `${Math.round((ownShip.throttle || 0) * 100)}%`)
    const v = ownShip.velocity || {x: 0, y: 0, z: 0}
    this.text("#hud-actual-speed", `${Math.round(Math.hypot(v.x, v.y, v.z))} u/s`)
    const a = orientationTelemetry(
      ownShip.orientation, ownShip.attitude || {yaw: 0, pitch: 0, roll: 0}
    )
    const deg = radians => Math.round(radians * 180 / Math.PI)
    this.text("#hud-heading", `${(deg(a.yaw) + 360) % 360}°`)
    this.text("#hud-pitch", `${deg(a.pitch)}°`)
    this.text("#hud-roll", `${deg(a.roll)}°`)
    const r = ownShip.angularVelocity || {yaw: 0, pitch: 0, roll: 0}
    this.text("#hud-turn-rates",
      `${Math.round(Math.abs(deg(r.pitch)))} / ${Math.round(Math.abs(deg(r.yaw)))} / ${Math.round(Math.abs(deg(r.roll)))} °/s`)
    const input = this.flightControls?.axes().pitch || 0
    this.text("#hud-pitch-input", input < 0 ? "DOWN" : input > 0 ? "UP" : "—")
  }

  updateNavigationStatus() {
    const ownShip = this.entities.get(this.selfId)
    let status = "Awaiting sector link"

    if (ownShip?.status === "destroyed") {
      status = "Navigation unavailable"
    } else if (this.commandDestination) {
      status = `Course locked · ${number(this.commandDestination.x)} / ${number(this.commandDestination.y)} / ${number(this.commandDestination.z)}`
    } else if (ownShip) {
      status = "Press M for atlas navigation"
    }

    this.text("#minimap-navigation-status", status)
  }

  updateCombatHud() {
    const ownShip = this.entities.get(this.selfId)
    if (ownShip) {
      this.text("#hud-hp", `${number(ownShip.hull)} / ${number(ownShip.maxHull)}`)
      this.text("#hud-shields", `${number(ownShip.shields)} / ${number(ownShip.maxShields)}`)
      this.text("#hud-compact-hp", number(ownShip.hull))
      this.text("#hud-compact-shields", number(ownShip.shields))
      this.setWidth("#hud-hp-bar", healthPercent(ownShip.hull, ownShip.maxHull))
      this.setWidth("#hud-shield-bar", healthPercent(ownShip.shields, ownShip.maxShields))
    }

    this.updateHotbar()
  }

  updateHotbar() {
    const ownShip = this.entities.get(this.selfId)
    const engaged = Boolean(ownShip?.engagedTargetId)
    const nextAttackTick = Number(ownShip?.nextAttackTick) || 0
    const cooldownTicks = Math.max(1, Number(ownShip?.attackCooldownTicks) || 1)
    const remainingTicks = Math.max(0, nextAttackTick - this.worldTick)
    const cooldownPercent = Math.min(100, remainingTicks / cooldownTicks * 100)

    for (const slot of this.root.querySelectorAll("[data-hotbar-slot]")) {
      const slotNumber = Number(slot.dataset.hotbarSlot)
      const hasAction = slot.dataset.actionId != null
      const action = {
        type: slot.dataset.actionType,
        activationMode: slot.dataset.activationMode,
      }
      const active = hasAction && hotbarActionActive(action, engaged)
      const coolingDown = hasAction && action.type === "ammunition" && remainingTicks > 0
      slot.classList.toggle("is-selected", slotNumber === this.selectedHotbarSlot)
      slot.classList.toggle("is-active", active)
      slot.classList.toggle("is-cooling-down", coolingDown)
      slot.setAttribute("aria-pressed", active ? "true" : "false")

      const cooldown = slot.querySelector("[data-hotbar-cooldown]")
      if (cooldown) cooldown.style.height = `${coolingDown ? cooldownPercent : 0}%`
    }

    this.text("#hotbar-mode", engaged ? "AUTOFIRE" : "STANDBY")
  }

  setWidth(selector, percentage) {
    const element = this.root.querySelector(selector)
    if (element) element.style.width = `${percentage}%`
  }

  setCombatMessage(message) {
    this.text("#combat-status", message)
  }

  resize() {
    const rect = this.canvas.getBoundingClientRect()
    const dpr = Math.min(window.devicePixelRatio || 1, 2)
    this.stereoView?.resize(rect.width, rect.height, dpr)
  }

  handleHelmetAlignmentKey(event) {
    const intent = helmetAlignmentKeyIntent(event, {
      active: !this.navComputer?.isOpen && this.helmet?.canAdjustAlignment(),
      typing: gameplayTypingTarget(event.target),
    })
    if (!intent) return
    event.preventDefault()
    event.stopPropagation()

    // Holding Left/Right is convenient inside a headset. Rate-limit repeat
    // packets instead of flooding Phoenix on a fast keyboard repeat setting.
    if (intent.axis === "gap") {
      const now = performance.now()
      if (event.repeat && now - (this.lastHelmetArrowAt || 0) < 90) return
      this.lastHelmetArrowAt = now
    }
    this.helmet.adjustAlignment(intent.axis, intent.direction)
  }

  handleDisplayModeKey(event) {
    if (event.defaultPrevented || this.navComputer?.isOpen) return
    if (event.repeat || event.ctrlKey || event.altKey || event.metaKey || event.key.toLowerCase() !== "v") return
    const element = event.target
    if (element?.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(element?.tagName)) return
    event.preventDefault()
    this.setDisplayMode(nextFlightMode(this.displayMode))
  }

  setDisplayMode(mode) {
    if (!validFlightMode(mode)) return false
    if (!this.stereoView) {
      try {
        this.stereoView = new StereoSpaceView(this.root.querySelector("#space-viewport-3d"))
      } catch (_error) {
        this.showError("WebGL is required for the 3D cockpit. Check browser GPU support.")
        const select = this.root.querySelector("#display-mode")
        if (select) select.value = "3d"
        return false
      }
    }
    this.navigation?.cancel()
    this.displayMode = mode
    this.root.dataset.displayMode = mode
    const select = this.root.querySelector("#display-mode")
    if (select) select.value = mode
    this.stereoView.setMode(mode)
    this.resize()
    return true
  }

  setConnection(label, state) {
    this.text("#connection-status", label)
    const indicator = this.root.querySelector("#connection-indicator")
    indicator.className = state === "online"
      ? "size-1.5 rounded-full bg-emerald-300 shadow-[0_0_10px_rgba(110,231,183,0.8)]"
      : "size-1.5 rounded-full bg-rose-400 shadow-[0_0_10px_rgba(251,113,133,0.8)]"
  }

  showError(message) {
    const element = this.root.querySelector("#game-error")
    element.textContent = message
    element.classList.remove("hidden")
    window.clearTimeout(this.errorTimer)
    this.errorTimer = window.setTimeout(() => element.classList.add("hidden"), 6000)
  }

  text(selector, value) {
    const element = this.root.querySelector(selector)
    if (element) element.textContent = value
  }
}

export const startGameClient = () => {
  const root = document.querySelector("#game-client")
  if (root) new SpaceClient(root).start()
}
