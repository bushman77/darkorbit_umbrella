import {Socket} from "phoenix"
import {GraphicsAssets} from "./asset_catalog"
import {
  applyAuthoritativeDamage,
  entityKey,
  findNpcAtScreenPoint,
  healthPercent,
  nearestNpc,
} from "./combat_client.mjs"
import {
  combatKeyIntent,
  desiredEntityAngle,
  smoothAngle,
} from "./combat_controls.mjs"
import {PointerNavigation} from "./pointer_navigation.mjs"

const clamp = (value, minimum, maximum) => Math.min(Math.max(value, minimum), maximum)
const number = value => new Intl.NumberFormat("en-US", {maximumFractionDigits: 0}).format(value || 0)

const seededRandom = seed => {
  let value = seed >>> 0
  return () => {
    value += 0x6D2B79F5
    let result = value
    result = Math.imul(result ^ (result >>> 15), result | 1)
    result ^= result + Math.imul(result ^ (result >>> 7), result | 61)
    return ((result ^ (result >>> 14)) >>> 0) / 4294967296
  }
}

class SpaceClient {
  constructor(root) {
    this.root = root
    this.canvas = root.querySelector("#space-viewport")
    this.context = this.canvas.getContext("2d", {alpha: false})
    this.mapId = root.dataset.mapId
    this.token = root.dataset.socketToken
    this.entities = new Map()
    this.pilots = new Map()
    this.boundaries = {width: 20000, height: 12000}
    this.camera = {x: 1000, y: 1000}
    this.viewport = {width: 1, height: 1, dpr: 1}
    this.selfId = null
    this.player = null
    this.commandDestination = null
    this.selectedTargetId = null
    this.selectedHotbarSlot = 1
    this.worldTick = 0
    this.tickMs = 100
    this.beams = []
    this.impacts = []
    this.explosions = []
    this.lastFrame = performance.now()
    this.assets = new GraphicsAssets()
    this.stars = this.createStars()
  }

  start() {
    if (!this.context) {
      this.showError("Canvas 2D is unavailable in this browser.")
      return
    }

    this.assets.preload()
    this.resize()
    window.addEventListener("resize", () => this.resize())
    this.navigation = new PointerNavigation({
      canvas: this.canvas,
      destinationForPointer: pointer => this.destinationForPointer(pointer),
      shipPosition: () => this.entities.get(this.selfId)?.target,
      sendDestination: destination => this.sendDestination(destination),
      interceptPointerDown: pointer => this.selectTargetAtPointer(pointer),
    }).attach()
    this.canvas.addEventListener("contextmenu", event => this.handleTargetPointer(event))
    this.root.querySelector("#combat-target-nearest")?.addEventListener("click", () => this.selectNearestTarget())
    this.root.querySelector("#combat-clear-target")?.addEventListener("click", () => this.disengageCombat())
    this.root.querySelector("#combat-fire")?.addEventListener("click", () => this.engageCombat())
    for (const slot of this.root.querySelectorAll("[data-hotbar-slot]")) {
      slot.addEventListener("click", () => this.activateHotbarSlot(Number(slot.dataset.hotbarSlot)))
    }
    window.addEventListener("keydown", event => this.handleCombatKey(event))
    this.connect()
    requestAnimationFrame(time => this.frame(time))
  }

  connect() {
    this.socket = new Socket("/socket", {params: {token: this.token}})
    this.socket.onOpen(() => this.setConnection("Relay connected", "online"))
    this.socket.onError(() => this.setConnection("Relay interrupted", "error"))
    this.socket.onClose(() => this.setConnection("Relay offline", "error"))
    this.socket.connect()

    this.channel = this.socket.channel(`world:${this.mapId}`, {})
    this.channel.on("world_state", state => this.applyWorldState(state))
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
    this.worldTick = response.map.tick
    this.tickMs = response.map.tick_ms
    this.pilots = new Map(Object.entries(response.pilots || {}))

    for (const entity of response.map.entities) this.upsertEntity(entity, true)
    this.syncOwnCombatState()

    const ownShip = this.entities.get(this.selfId)
    if (ownShip) this.camera = {...ownShip.render}

    this.populateHud()
    this.setConnection("Authoritative sync", "online")
  }

  applyWorldState(state) {
    this.boundaries = state.boundaries || this.boundaries
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
    const target = {x: entity.position.x, y: entity.position.y}
    const destination = entity.destination

    if (existing) {
      existing.target = target
      existing.destination = destination
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
  }

  destinationForPointer(pointer) {
    const rect = this.canvas.getBoundingClientRect()
    return {
      x: clamp(pointer.clientX - rect.left + this.camera.x - this.viewport.width / 2, 0, this.boundaries.width),
      y: clamp(pointer.clientY - rect.top + this.camera.y - this.viewport.height / 2, 0, this.boundaries.height),
    }
  }

  sendDestination(destination) {
    if (!this.channel || !this.selfId) return false

    this.commandDestination = destination
    this.channel
      .push("move", destination, 5000)
      .receive("error", response => this.showError(`Navigation rejected: ${response.reason}`))
      .receive("timeout", () => this.showError("Navigation command timed out."))

    return true
  }

  handleTargetPointer(event) {
    event.preventDefault()
    this.selectTargetAtPointer({clientX: event.clientX, clientY: event.clientY})
  }

  selectTargetAtPointer(pointer) {
    const rect = this.canvas.getBoundingClientRect()
    const target = findNpcAtScreenPoint(
      this.entities.values(),
      {x: pointer.clientX - rect.left, y: pointer.clientY - rect.top},
      position => this.worldToScreen(position),
      () => this.npcRenderDimensions()
    )

    if (!target) return false
    this.selectTarget(target.id)
    return true
  }

  npcRenderDimensions() {
    const {definition} = this.assets.get("npcs", "sentinel")
    return {width: definition?.width || 60, height: definition?.height || 60}
  }

  handleCombatKey(event) {
    const intent = combatKeyIntent(event)
    if (!intent) return

    event.preventDefault()
    if (intent.type === "engage") this.engageCombat()
    if (intent.type === "disengage") this.disengageCombat()
    if (intent.type === "activate_slot") this.activateHotbarSlot(intent.slot)
  }

  selectNearestTarget() {
    const ownShip = this.entities.get(this.selfId)
    const target = nearestNpc(this.entities.values(), ownShip?.target)
    if (target) this.selectTarget(target.id)
    else this.setCombatMessage("No hostile signal in sector telemetry.")
  }

  selectTarget(targetId) {
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

  activateHotbarSlot(slot) {
    if (!this.channel || !this.selfId || !Number.isInteger(slot)) return

    this.selectedHotbarSlot = slot
    this.updateHotbar()
    this.channel
      .push("activate_action", {slot}, 5000)
      .receive("ok", activation => {
        if (activation.status === "empty") {
          this.setCombatMessage(`Action slot ${slot === 10 ? 0 : slot} is empty.`)
        } else if (activation.engagement) {
          this.combatEngaged(activation.engagement)
        }
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
    this.selectedHotbarSlot = 1
    this.setCombatMessage("Pulse emitter engaged. Automatic fire authorized.")
    this.updateCombatHud()
  }

  combatDisengaged(engagement) {
    const player = this.entities.get(entityKey(engagement.player_id))
    if (player) player.engagedTargetId = null
    if (entityKey(engagement.player_id) !== this.selfId) return

    this.setCombatMessage("Combat disengaged.")
    this.updateCombatHud()
  }

  syncOwnCombatState() {
    const ownShip = this.entities.get(this.selfId)
    if (!ownShip) return
    this.selectedTargetId = ownShip.targetId
  }

  laserFired(attack) {
    const attacker = this.entities.get(entityKey(attack.attacker_id))
    const target = this.entities.get(entityKey(attack.target_id))
    if (target) applyAuthoritativeDamage(target, attack.target)
    if (attacker) attacker.nextAttackTick = attack.next_attack_tick
    this.worldTick = Math.max(this.worldTick, Number(attack.tick) || 0)

    const startedAt = performance.now()
    if (attacker && target) {
      this.beams.push({
        from: {...attacker.render},
        to: {...target.render},
        hostile: attacker.kind === "npc",
        startedAt,
        expiresAt: startedAt + 230,
      })
      this.impacts.push({
        position: {...target.render},
        shield: Number(attack.shield_damage) > 0,
        startedAt,
        expiresAt: startedAt + 420,
      })
    }

    if (entityKey(attack.attacker_id) === this.selfId) {
      this.setCombatMessage(
        `${number(attack.shield_damage)} shield · ${number(attack.hull_damage)} hull damage`
      )
    }

    this.updateCombatHud()
  }

  entityDestroyed(destruction) {
    const id = entityKey(destruction.entity.id)
    const entity = this.entities.get(id)
    const position = entity?.render || destruction.entity.position
    const startedAt = performance.now()

    if (position) {
      this.explosions.push({position: {...position}, startedAt, expiresAt: startedAt + 850})
    }

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
    this.draw(time)
    this.updateCoordinates()
    this.updateCombatHud()
    requestAnimationFrame(nextTime => this.frame(nextTime))
  }

  interpolate(deltaSeconds) {
    const positionBlend = 1 - Math.exp(-deltaSeconds / 0.085)

    for (const entity of this.entities.values()) {
      entity.render.x += (entity.target.x - entity.render.x) * positionBlend
      entity.render.y += (entity.target.y - entity.render.y) * positionBlend
    }

    const rotationBlend = 1 - Math.exp(-deltaSeconds / 0.075)
    for (const entity of this.entities.values()) {
      entity.angle = smoothAngle(
        entity.angle,
        desiredEntityAngle(entity, this.entities),
        rotationBlend
      )
    }

    const ownShip = this.entities.get(this.selfId)
    if (!ownShip) return

    const cameraTarget = this.clampedCamera(ownShip.render)
    const cameraBlend = 1 - Math.exp(-deltaSeconds / 0.14)
    this.camera.x += (cameraTarget.x - this.camera.x) * cameraBlend
    this.camera.y += (cameraTarget.y - this.camera.y) * cameraBlend
  }

  clampedCamera(position) {
    const halfWidth = this.viewport.width / 2
    const halfHeight = this.viewport.height / 2
    const x = this.boundaries.width <= this.viewport.width
      ? this.boundaries.width / 2
      : clamp(position.x, halfWidth, this.boundaries.width - halfWidth)
    const y = this.boundaries.height <= this.viewport.height
      ? this.boundaries.height / 2
      : clamp(position.y, halfHeight, this.boundaries.height - halfHeight)
    return {x, y}
  }

  draw(time) {
    const context = this.context
    context.setTransform(this.viewport.dpr, 0, 0, this.viewport.dpr, 0, 0)
    const gradient = context.createRadialGradient(
      this.viewport.width * 0.52,
      this.viewport.height * 0.42,
      20,
      this.viewport.width * 0.52,
      this.viewport.height * 0.42,
      Math.max(this.viewport.width, this.viewport.height)
    )
    gradient.addColorStop(0, "#071426")
    gradient.addColorStop(0.55, "#030a16")
    gradient.addColorStop(1, "#01040a")
    context.fillStyle = gradient
    context.fillRect(0, 0, this.viewport.width, this.viewport.height)

    this.drawStars(time)
    this.drawGrid()
    this.drawBoundary()
    this.drawDestination(time)

    const orderedEntities = [...this.entities.values()].sort((left, right) => {
      const kindOrder = (left.kind === "player" ? 0 : 1) - (right.kind === "player" ? 0 : 1)
      return kindOrder || left.id.localeCompare(right.id)
    })
    for (const entity of orderedEntities) this.drawEntity(entity, time)

    this.drawCombatEffects(time)
    this.drawMinimap()
  }

  drawStars(time) {
    const context = this.context
    for (const star of this.stars) {
      const width = this.viewport.width + 120
      const height = this.viewport.height + 120
      const x = ((star.x * width - this.camera.x * star.depth * 0.11) % width + width) % width - 60
      const y = ((star.y * height - this.camera.y * star.depth * 0.11) % height + height) % height - 60
      const shimmer = 0.72 + Math.sin(time * 0.0018 + star.phase) * 0.28
      context.globalAlpha = star.alpha * shimmer
      context.fillStyle = star.tint
      context.beginPath()
      context.arc(x, y, star.radius, 0, Math.PI * 2)
      context.fill()
    }
    context.globalAlpha = 1
  }

  drawGrid() {
    const context = this.context
    const spacing = 500
    const left = this.camera.x - this.viewport.width / 2
    const top = this.camera.y - this.viewport.height / 2
    const right = left + this.viewport.width
    const bottom = top + this.viewport.height
    context.lineWidth = 1
    context.strokeStyle = "rgba(103, 232, 249, 0.035)"
    context.beginPath()

    for (let x = Math.floor(left / spacing) * spacing; x <= right; x += spacing) {
      const screen = this.worldToScreen({x, y: 0})
      context.moveTo(Math.round(screen.x) + 0.5, 0)
      context.lineTo(Math.round(screen.x) + 0.5, this.viewport.height)
    }
    for (let y = Math.floor(top / spacing) * spacing; y <= bottom; y += spacing) {
      const screen = this.worldToScreen({x: 0, y})
      context.moveTo(0, Math.round(screen.y) + 0.5)
      context.lineTo(this.viewport.width, Math.round(screen.y) + 0.5)
    }
    context.stroke()
  }

  drawBoundary() {
    const context = this.context
    const origin = this.worldToScreen({x: 0, y: 0})
    context.save()
    context.strokeStyle = "rgba(103, 232, 249, 0.65)"
    context.lineWidth = 2
    context.setLineDash([10, 8])
    context.shadowColor = "rgba(34, 211, 238, 0.4)"
    context.shadowBlur = 12
    context.strokeRect(origin.x, origin.y, this.boundaries.width, this.boundaries.height)
    context.restore()
  }

  drawDestination(time) {
    if (!this.commandDestination) return
    const context = this.context
    const screen = this.worldToScreen(this.commandDestination)
    const pulse = 12 + Math.sin(time * 0.006) * 3
    context.save()
    context.strokeStyle = "rgba(103, 232, 249, 0.8)"
    context.lineWidth = 1.5
    context.beginPath()
    context.arc(screen.x, screen.y, pulse, 0, Math.PI * 2)
    context.moveTo(screen.x - 18, screen.y)
    context.lineTo(screen.x + 18, screen.y)
    context.moveTo(screen.x, screen.y - 18)
    context.lineTo(screen.x, screen.y + 18)
    context.stroke()
    context.restore()
  }

  drawEntity(entity, time) {
    if (entity.kind === "npc") this.drawNpc(entity, time)
    else this.drawShip(entity, time)
  }

  drawShip(entity, time) {
    const context = this.context
    const screen = this.worldToScreen(entity.render)
    const isSelf = entity.id === this.selfId
    const assetName = isSelf ? "localScout" : "remoteScout"
    const {definition, image} = this.assets.get("ships", assetName)
    const width = definition?.width || 68
    const height = definition?.height || 52

    context.save()
    context.translate(screen.x, screen.y)
    context.rotate(entity.angle + Math.PI / 2)

    if (entity.destination) {
      const exhaust = 12 + Math.sin(time * 0.018 + Number(entity.id)) * 4
      const exhaustGradient = context.createLinearGradient(0, height / 4, 0, height / 2 + exhaust)
      exhaustGradient.addColorStop(0, isSelf ? "rgba(103,232,249,0.85)" : "rgba(196,181,253,0.8)")
      exhaustGradient.addColorStop(1, "rgba(37,99,235,0)")
      context.fillStyle = exhaustGradient
      context.beginPath()
      context.moveTo(-7, height * 0.28)
      context.lineTo(0, height * 0.5 + exhaust)
      context.lineTo(7, height * 0.28)
      context.closePath()
      context.fill()
    }

    context.shadowColor = isSelf ? "rgba(34,211,238,0.6)" : "rgba(167,139,250,0.5)"
    context.shadowBlur = isSelf ? 18 : 12
    if (image) {
      context.drawImage(image, -width / 2, -height / 2, width, height)
    } else {
      this.drawFallbackShip(context, isSelf, width, height)
    }
    context.restore()

    const pilot = this.pilots.get(entity.playerId)
    context.textAlign = "center"
    context.font = isSelf ? "600 12px ui-sans-serif" : "500 11px ui-sans-serif"
    context.fillStyle = isSelf ? "#a5f3fc" : "#ddd6fe"
    context.fillText(pilot?.pilot_name || `Pilot ${entity.playerId}`, screen.x, screen.y + height / 2 + 17)
  }

  drawNpc(entity, time) {
    const context = this.context
    const screen = this.worldToScreen(entity.render)
    const {definition, image} = this.assets.get("npcs", "sentinel")
    const width = definition?.width || 60
    const height = definition?.height || 60
    const selected = entity.id === this.selectedTargetId

    context.save()
    context.translate(screen.x, screen.y)

    if (selected) {
      const pulse = 39 + Math.sin(time * 0.009) * 4
      context.strokeStyle = "rgba(251, 146, 60, 0.95)"
      context.lineWidth = 2
      context.setLineDash([7, 5])
      context.beginPath()
      context.arc(0, 0, pulse, 0, Math.PI * 2)
      context.stroke()
      context.setLineDash([])
    }

    context.rotate(entity.angle + Math.PI / 2)
    context.shadowColor = selected ? "rgba(251,146,60,0.9)" : "rgba(249,115,22,0.48)"
    context.shadowBlur = selected ? 22 : 12
    if (image) {
      context.drawImage(image, -width / 2, -height / 2, width, height)
    } else {
      this.drawFallbackNpc(context, width, height)
    }
    context.restore()

    this.drawEntityBars(entity, screen, width)
    context.textAlign = "center"
    context.font = selected ? "700 12px ui-sans-serif" : "600 11px ui-sans-serif"
    context.fillStyle = selected ? "#fed7aa" : "#fdba74"
    context.fillText(entity.displayName || "Hostile", screen.x, screen.y + height / 2 + 28)
    context.font = "600 8px ui-sans-serif"
    context.fillStyle = "rgba(251,146,60,0.68)"
    context.fillText((entity.state || "idle").toUpperCase(), screen.x, screen.y + height / 2 + 40)
  }

  drawFallbackNpc(context, width, height) {
    context.fillStyle = "#431407"
    context.strokeStyle = "#fb923c"
    context.lineWidth = 2
    context.beginPath()
    context.moveTo(0, -height / 2)
    context.lineTo(width / 2, 0)
    context.lineTo(0, height / 2)
    context.lineTo(-width / 2, 0)
    context.closePath()
    context.fill()
    context.stroke()
  }

  drawEntityBars(entity, screen, width) {
    const context = this.context
    const barWidth = Math.max(46, width)
    const left = screen.x - barWidth / 2
    const top = screen.y - width / 2 - 14
    context.fillStyle = "rgba(2,6,23,0.82)"
    context.fillRect(left, top, barWidth, 7)
    context.fillStyle = "#38bdf8"
    context.fillRect(left, top, barWidth * healthPercent(entity.shields, entity.maxShields) / 100, 2)
    context.fillStyle = "#34d399"
    context.fillRect(left, top + 4, barWidth * healthPercent(entity.hull, entity.maxHull) / 100, 3)
  }

  drawCombatEffects(time) {
    this.beams = this.beams.filter(beam => beam.expiresAt > time)
    this.impacts = this.impacts.filter(impact => impact.expiresAt > time)
    this.explosions = this.explosions.filter(explosion => explosion.expiresAt > time)

    for (const beam of this.beams) this.drawBeam(beam, time)
    for (const impact of this.impacts) this.drawImpact(impact, time)
    for (const explosion of this.explosions) this.drawExplosion(explosion, time)
  }

  drawBeam(beam, time) {
    const context = this.context
    const from = this.worldToScreen(beam.from)
    const to = this.worldToScreen(beam.to)
    const deltaX = to.x - from.x
    const deltaY = to.y - from.y
    const length = Math.hypot(deltaX, deltaY)
    const progress = clamp((time - beam.startedAt) / (beam.expiresAt - beam.startedAt), 0, 1)
    const {definition, image} = this.assets.get("lasers", "pulse")

    context.save()
    context.translate(from.x, from.y)
    context.rotate(Math.atan2(deltaY, deltaX))
    context.globalAlpha = 1 - progress * 0.72
    context.shadowColor = beam.hostile ? "#fb923c" : "#22d3ee"
    context.shadowBlur = 16 + Math.sin(progress * Math.PI) * 12

    if (image) {
      context.drawImage(image, 0, -(definition?.height || 8) / 2, length, definition?.height || 8)
    } else {
      context.strokeStyle = beam.hostile ? "#fdba74" : "#a5f3fc"
      context.lineWidth = 3 + Math.sin(progress * Math.PI) * 2
      context.beginPath()
      context.moveTo(0, 0)
      context.lineTo(length, 0)
      context.stroke()
    }
    context.restore()
  }

  drawImpact(impact, time) {
    const context = this.context
    const screen = this.worldToScreen(impact.position)
    const progress = clamp((time - impact.startedAt) / (impact.expiresAt - impact.startedAt), 0, 1)
    context.save()
    context.globalAlpha = 1 - progress
    context.strokeStyle = impact.shield ? "#67e8f9" : "#fb923c"
    context.lineWidth = 4 - progress * 2
    context.shadowColor = context.strokeStyle
    context.shadowBlur = 18
    context.beginPath()
    context.arc(screen.x, screen.y, 18 + progress * 30, 0, Math.PI * 2)
    context.stroke()
    context.restore()
  }

  drawExplosion(explosion, time) {
    const context = this.context
    const screen = this.worldToScreen(explosion.position)
    const progress = clamp((time - explosion.startedAt) / (explosion.expiresAt - explosion.startedAt), 0, 1)
    const {definition, image} = this.assets.get("explosions", "plasma")
    const size = (definition?.width || 96) * (0.45 + progress * 1.25)
    context.save()
    context.translate(screen.x, screen.y)
    context.rotate(progress * 1.8)
    context.globalAlpha = 1 - progress
    context.shadowColor = "#f97316"
    context.shadowBlur = 28
    if (image) context.drawImage(image, -size / 2, -size / 2, size, size)
    else {
      context.fillStyle = "#fb923c"
      context.beginPath()
      context.arc(0, 0, size / 3, 0, Math.PI * 2)
      context.fill()
    }
    context.restore()
  }

  drawFallbackShip(context, isSelf, width, height) {
    context.fillStyle = isSelf ? "#102b3b" : "#211939"
    context.strokeStyle = isSelf ? "#67e8f9" : "#c4b5fd"
    context.lineWidth = 2
    context.beginPath()
    context.moveTo(0, -height / 2)
    context.lineTo(width / 2, height / 3)
    context.lineTo(10, height / 5)
    context.lineTo(0, height / 2)
    context.lineTo(-10, height / 5)
    context.lineTo(-width / 2, height / 3)
    context.closePath()
    context.fill()
    context.stroke()
  }

  drawMinimap() {
    const context = this.context
    const mapWidth = this.viewport.width < 640 ? 118 : 166
    const mapHeight = mapWidth * (this.boundaries.height / this.boundaries.width)
    const x = this.viewport.width - mapWidth - 20
    const y = this.viewport.width < 640 ? 86 : 98
    context.save()
    context.fillStyle = "rgba(2, 6, 23, 0.78)"
    context.strokeStyle = "rgba(103, 232, 249, 0.35)"
    context.lineWidth = 1
    context.beginPath()
    context.roundRect(x - 8, y - 20, mapWidth + 16, mapHeight + 30, 10)
    context.fill()
    context.stroke()
    context.fillStyle = "rgba(148, 163, 184, 0.8)"
    context.font = "600 9px ui-sans-serif"
    context.textAlign = "left"
    context.fillText("MAP BOUNDARY", x, y - 7)
    context.strokeStyle = "rgba(103, 232, 249, 0.6)"
    context.strokeRect(x, y, mapWidth, mapHeight)

    for (const entity of this.entities.values()) {
      const dotX = x + (entity.render.x / this.boundaries.width) * mapWidth
      const dotY = y + (entity.render.y / this.boundaries.height) * mapHeight
      context.fillStyle = entity.kind === "npc"
        ? "#fb923c"
        : entity.id === this.selfId ? "#67e8f9" : "#c4b5fd"
      context.beginPath()
      context.arc(dotX, dotY, entity.id === this.selfId ? 2.5 : 2, 0, Math.PI * 2)
      context.fill()
    }
    context.restore()
  }

  worldToScreen(position) {
    return {
      x: position.x - this.camera.x + this.viewport.width / 2,
      y: position.y - this.camera.y + this.viewport.height / 2,
    }
  }

  populateHud() {
    const {pilot, ship, stats, configuration} = this.player
    this.text("#hud-pilot", pilot.pilot_name)
    this.text("#hud-ship", `${ship.name} · Pilot #${pilot.id}`)
    this.text("#hud-config", `C-${configuration.number}`)
    this.text("#hud-hp", `${number(stats.hit_points)} / ${number(stats.hit_points)}`)
    this.text("#hud-shields", `${number(stats.shields)} / ${number(stats.shields)}`)
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
    this.text("#hud-coordinates", `${number(ownShip.render.x)} / ${number(ownShip.render.y)}`)
  }

  updateCombatHud() {
    const ownShip = this.entities.get(this.selfId)
    if (ownShip) {
      this.text("#hud-hp", `${number(ownShip.hull)} / ${number(ownShip.maxHull)}`)
      this.text("#hud-shields", `${number(ownShip.shields)} / ${number(ownShip.maxShields)}`)
      this.setWidth("#hud-hp-bar", healthPercent(ownShip.hull, ownShip.maxHull))
      this.setWidth("#hud-shield-bar", healthPercent(ownShip.shields, ownShip.maxShields))
    }

    this.updateHotbar()

    const target = this.entities.get(this.selectedTargetId)
    const panel = this.root.querySelector("#combat-target-panel")
    if (!panel) return

    if (target?.kind === "npc") {
      panel.classList.remove("hidden")
      this.text("#combat-target-name", target.displayName || "Hostile")
      const engagement = ownShip?.engagedTargetId === target.id ? "ENGAGED" : "SELECTED"
      this.text(
        "#combat-target-state",
        `${engagement} · ${(target.state || "idle").toUpperCase()} · ${number(target.attackRange)}u weapons`
      )
      this.text("#combat-target-hull", `${number(target.hull)} / ${number(target.maxHull)}`)
      this.text("#combat-target-shields", `${number(target.shields)} / ${number(target.maxShields)}`)
      this.setWidth("#combat-target-hull-bar", healthPercent(target.hull, target.maxHull))
      this.setWidth("#combat-target-shield-bar", healthPercent(target.shields, target.maxShields))
    } else {
      panel.classList.add("hidden")
    }
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
      const active = hasAction && engaged && slotNumber === 1
      const coolingDown = hasAction && remainingTicks > 0
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
    this.viewport = {width: rect.width, height: rect.height, dpr}
    this.canvas.width = Math.max(1, Math.floor(rect.width * dpr))
    this.canvas.height = Math.max(1, Math.floor(rect.height * dpr))
  }

  createStars() {
    const random = seededRandom(0x0B17)
    const tints = ["#ffffff", "#bae6fd", "#c7d2fe", "#a5f3fc"]
    return Array.from({length: 260}, () => ({
      x: random(),
      y: random(),
      depth: 0.18 + random() * 0.82,
      radius: 0.35 + random() * 1.25,
      alpha: 0.28 + random() * 0.62,
      phase: random() * Math.PI * 2,
      tint: tints[Math.floor(random() * tints.length)],
    }))
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
