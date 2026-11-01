import {Socket} from "phoenix"
import {GraphicsAssets} from "./asset_catalog"

const clamp = (value, minimum, maximum) => Math.min(Math.max(value, minimum), maximum)
const entityKey = id => String(id)
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
    this.canvas.addEventListener("pointerdown", event => this.navigate(event))
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
    this.channel.on("entity_left", entity => this.entities.delete(entityKey(entity.id)))
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
    this.pilots = new Map(Object.entries(response.pilots || {}))

    for (const entity of response.map.entities) this.upsertEntity(entity, true)

    const ownShip = this.entities.get(this.selfId)
    if (ownShip) this.camera = {...ownShip.render}

    this.populateHud()
    this.setConnection("Authoritative sync", "online")
  }

  applyWorldState(state) {
    this.boundaries = state.boundaries || this.boundaries
    const activeIds = new Set()

    for (const entity of state.entities) {
      activeIds.add(entityKey(entity.id))
      this.upsertEntity(entity)
    }

    for (const id of this.entities.keys()) {
      if (!activeIds.has(id)) this.entities.delete(id)
    }
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
      if (destination) existing.angle = Math.atan2(destination.y - existing.render.y, destination.x - existing.render.x)
      if (snap) existing.render = {...target}
    } else {
      this.entities.set(id, {
        id,
        playerId: entityKey(entity.player_id),
        render: {...target},
        target,
        destination,
        speed: entity.speed,
        angle: destination ? Math.atan2(destination.y - target.y, destination.x - target.x) : -Math.PI / 2,
      })
    }
  }

  navigate(event) {
    if (!this.channel || !this.selfId || event.button !== 0) return

    const rect = this.canvas.getBoundingClientRect()
    const destination = {
      x: clamp(event.clientX - rect.left + this.camera.x - this.viewport.width / 2, 0, this.boundaries.width),
      y: clamp(event.clientY - rect.top + this.camera.y - this.viewport.height / 2, 0, this.boundaries.height),
    }

    this.commandDestination = destination
    this.channel
      .push("move", destination, 5000)
      .receive("error", response => this.showError(`Navigation rejected: ${response.reason}`))
      .receive("timeout", () => this.showError("Navigation command timed out."))
  }

  frame(time) {
    const deltaSeconds = Math.min((time - this.lastFrame) / 1000, 0.1)
    this.lastFrame = time
    this.interpolate(deltaSeconds)
    this.draw(time)
    this.updateCoordinates()
    requestAnimationFrame(nextTime => this.frame(nextTime))
  }

  interpolate(deltaSeconds) {
    const positionBlend = 1 - Math.exp(-deltaSeconds / 0.085)

    for (const entity of this.entities.values()) {
      entity.render.x += (entity.target.x - entity.render.x) * positionBlend
      entity.render.y += (entity.target.y - entity.render.y) * positionBlend
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

    const orderedEntities = [...this.entities.values()].sort((left, right) => Number(left.id) - Number(right.id))
    for (const entity of orderedEntities) this.drawShip(entity, time)

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
      context.fillStyle = entity.id === this.selfId ? "#67e8f9" : "#c4b5fd"
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
    this.text("#hud-equipment", equipment.length ? equipment.map(item => item.name).join(" · ") : "Base ship systems")
  }

  updateCoordinates() {
    const ownShip = this.entities.get(this.selfId)
    if (!ownShip) return
    this.text("#hud-coordinates", `${number(ownShip.render.x)} / ${number(ownShip.render.y)}`)
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
