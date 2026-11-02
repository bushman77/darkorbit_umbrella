import {
  MAX_WAYPOINTS, chartProjection, chartWorldPoint,
  appendWaypoint, routeDistance, parseCoordinates,
} from "./navigation_math.mjs"

const NS = "http://www.w3.org/2000/svg"
const number = value => Math.round(value).toLocaleString("en-US")
const coordText = point => point ?
  `${number(point.x)} / ${number(point.y)} / Z ${number(point.z ?? 0)}` : "— / — / Z —"

function element(name, attributes = {}, label = null) {
  const node = document.createElementNS(NS, name)
  for (const [attribute, value] of Object.entries(attributes)) node.setAttribute(attribute, String(value))
  if (label != null) node.textContent = String(label)
  return node
}

function drawLink(group, projection, from, to, color, dashed = false) {
  const a = projection.point(from)
  const b = projection.point(to)
  group.appendChild(element("line", {
    x1: a.x, y1: a.y, x2: b.x, y2: b.y,
    stroke: color, "stroke-width": 2.3,
    "stroke-dasharray": dashed ? "8 7" : "none",
    opacity: 0.9,
  }))
}

export class NavigationComputer {
  constructor({root, getEntities, getSelfId, getBoundaries, isConnected, engage, halt, onOpen, onClose}) {
    this.root = root
    this.getEntities = getEntities
    this.getSelfId = getSelfId
    this.getBoundaries = getBoundaries
    this.isConnected = isConnected
    this.engage = engage
    this.halt = halt
    this.onOpen = onOpen
    this.onClose = onClose
    this.draft = []
    this.isOpen = false
    this.pending = false
    this.lastDrawAt = -Infinity
  }

  start() {
    this.svg = this.root.querySelector("#nav-chart")
    this.chartLayer = this.root.querySelector("#nav-chart-content")
    this.root.querySelector("#nav-close")?.addEventListener("click", () => this.close())
    this.root.querySelector("#nav-clear")?.addEventListener("click", () => {
      this.draft = []
      this.note("Draft cleared. Active server course unchanged.")
      this.draw(0, true)
    })
    this.root.querySelector("#nav-undo")?.addEventListener("click", () => {
      this.draft.pop()
      this.note("Last draft waypoint removed.")
      this.draw(0, true)
    })
    this.root.querySelector("#nav-engage")?.addEventListener("click", () => this.submit())
    this.root.querySelector("#nav-stop")?.addEventListener("click", () => this.stop())
    this.root.querySelector("#nav-coordinate-form")?.addEventListener("submit", event => {
      event.preventDefault()
      const x = this.root.querySelector("#nav-x").value
      const y = this.root.querySelector("#nav-y").value
      const z = this.root.querySelector("#nav-z").value
      const point = parseCoordinates(x, y, this.getBoundaries(), z)
      this.addWaypoint(point)
    })
    this.svg.addEventListener("click", event => {
      const matrix = this.svg.getScreenCTM()
      if (!matrix) return
      const pointer = this.svg.createSVGPoint()
      pointer.x = event.clientX
      pointer.y = event.clientY
      const local = pointer.matrixTransform(matrix.inverse())
      const xy = chartWorldPoint({x: local.x, y: local.y}, this.getBoundaries())
      const altitude = this.root.querySelector("#nav-z").value
      if (altitude.trim() === "") {
        this.note("Enter a waypoint altitude before selecting a position.")
        return
      }
      const z = Number(altitude)
      this.addWaypoint(xy && {...xy, z})
    })
    return this
  }

  ownShip() {
    return this.getEntities().get(this.getSelfId())
  }

  open() {
    if (this.isOpen) return
    this.isOpen = true
    this.root.hidden = false
    const altitude = this.root.querySelector("#nav-z")
    const bounds = this.getBoundaries()
    altitude.min = String(bounds.altitude_min ?? -3000)
    altitude.max = String(bounds.altitude_max ?? 3000)
    // Default to current altitude for a new chart session, but permit changes.
    if (!this.draft.length) altitude.value = String(this.ownShip()?.target?.z ?? 0)
    this.onOpen?.()
    this.note("Click the chart to plot waypoints. Engage to hand the course to the helm.")
    this.draw(0, true)
    this.root.querySelector("#nav-close")?.focus()
  }

  close() {
    if (!this.isOpen) return
    this.isOpen = false
    this.root.hidden = true
    this.onClose?.()
  }

  handleKey(event) {
    if (event.defaultPrevented || event.repeat) return false
    if (this.isOpen && event.code === "Escape") {
      event.preventDefault()
      this.close()
      return true
    }
    // Tab and Shift+Tab remain inside the modal navigation computer.
    if (this.isOpen && event.code === "Tab" && !event.altKey && !event.ctrlKey && !event.metaKey) {
      const focusable = [...this.root.querySelectorAll("button:not(:disabled), input:not(:disabled)")].filter(node => !node.hidden)
      const first = focusable[0]
      const last = focusable.at(-1)
      if ((event.shiftKey && document.activeElement === first) ||
          (!event.shiftKey && document.activeElement === last)) {
        event.preventDefault()
        ;(event.shiftKey ? last : first)?.focus()
        return true
      }
    }
    if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return false
    const tag = event.target?.tagName
    const editing = event.target?.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(tag)
    if (event.code === "KeyM" && !editing) {
      event.preventDefault()
      this.isOpen ? this.close() : this.open()
      return true
    }
    return false
  }

  addWaypoint(point) {
    const updated = appendWaypoint(this.draft, point, this.getBoundaries())
    if (updated === this.draft) {
      this.note(`Waypoint rejected — select a position within the sector, up to ${MAX_WAYPOINTS} legs.`)
      return
    }
    this.draft = updated
    this.note(`Waypoint ${this.draft.length} plotted. Engage autopilot when ready.`)
    this.draw(0, true)
  }

  submit() {
    if (this.pending || !this.isConnected() || !this.draft.length) return
    this.pending = true
    this.refreshStatus()
    const waypoints = this.draft.map(({x, y, z}) => ({x, y, z: z ?? 0}))
    this.engage(waypoints, (ok, reason) => {
      this.pending = false
      if (ok) {
        this.draft = []
        this.note("Course accepted by authoritative helm. Ship en route.")
      } else {
        this.note(`Course rejected: ${reason || "network unavailable"}`)
      }
      this.draw(0, true)
    })
  }

  stop() {
    if (this.pending || !this.isConnected()) return
    this.pending = true
    this.refreshStatus()
    this.halt((ok, reason) => {
      this.pending = false
      this.note(ok ? "Helm stopped by server. Route cancelled." : `Stop failed: ${reason || "network unavailable"}`)
      this.draw(0, true)
    })
  }

  note(message) {
    this.root.querySelector("#nav-message").textContent = message
  }

  refreshStatus() {
    const self = this.ownShip()
    const running = self?.navigationMode === "autopilot" && Boolean(self?.destination)
    const legs = (self?.routeWaypoints?.length || 0) + (self?.destination ? 1 : 0)
    const connected = this.isConnected()
    this.root.querySelector("#nav-state").textContent =
      !connected ? "DISCONNECTED" : running ? `AUTOPILOT ACTIVE · ${legs} leg(s) left` :
      self?.destination ? "MANUAL STEERING" : "HELM IDLE"
    this.root.querySelector("#nav-position").textContent = coordText(self?.target)
    const preview = this.draft.length ? this.draft : (running ? [self.destination, ...self.routeWaypoints] : [])
    this.root.querySelector("#nav-distance").textContent = `${number(routeDistance(self?.target, preview))} units`
    this.root.querySelector("#nav-engage").disabled = this.pending || !connected || !this.draft.length
    this.root.querySelector("#nav-stop").disabled = this.pending || !connected || !self?.destination
    this.root.querySelector("#nav-undo").disabled = this.pending || !this.draft.length
    this.root.querySelector("#nav-clear").disabled = this.pending || !this.draft.length
    const list = this.root.querySelector("#nav-waypoints")
    list.replaceChildren()
    const routeList = this.draft.length ? this.draft :
      running ? [self.destination, ...self.routeWaypoints] : []
    for (const [index, waypoint] of routeList.entries()) {
      const item = document.createElement("li")
      const prefix = this.draft.length ? "WP" : "ACTIVE"
      item.textContent = `${prefix} ${index + 1}   ${coordText(waypoint)}`
      list.appendChild(item)
    }
    this.root.querySelector("#nav-waypoint-count").textContent =
      this.draft.length ? `${this.draft.length} / ${MAX_WAYPOINTS} DRAFT` :
      running ? `${routeList.length} ACTIVE` : `0 / ${MAX_WAYPOINTS}`
  }

  draw(time, force = false) {
    if (!this.isOpen || (!force && time - this.lastDrawAt < 100)) return
    this.lastDrawAt = time
    this.refreshStatus()
    const projection = chartProjection(this.getBoundaries())
    if (!projection) return
    const layer = this.chartLayer
    layer.replaceChildren()
    layer.appendChild(element("rect", {
      x: projection.x, y: projection.y, width: projection.width, height: projection.height,
      fill: "rgba(5,31,52,.48)", stroke: "#3a8da7", "stroke-width": 1.6,
    }))
    const bounds = this.getBoundaries()
    for (let x = 2000; x < bounds.width; x += 2000) {
      const p = projection.point({x, y: 0})
      layer.appendChild(element("line", {x1: p.x, y1: projection.y, x2: p.x,
        y2: projection.y + projection.height, stroke: "#21516d", opacity: 0.55}))
    }
    for (let y = 2000; y < bounds.height; y += 2000) {
      const p = projection.point({x: 0, y})
      layer.appendChild(element("line", {x1: projection.x, y1: p.y,
        x2: projection.x + projection.width, y2: p.y, stroke: "#21516d", opacity: 0.55}))
    }
    const own = this.ownShip()
    const active = own?.navigationMode === "autopilot" && own.destination
      ? [own.destination, ...(own.routeWaypoints || [])] : []
    const waypoints = this.draft.length ? this.draft : active
    const routeColor = this.draft.length ? "#73edf7" : "#fac17e"
    if (own?.render && waypoints.length) {
      let previous = own.render
      for (const [index, point] of waypoints.entries()) {
        drawLink(layer, projection, previous, point, routeColor, true)
        const pos = projection.point(point)
        layer.appendChild(element("circle", {cx: pos.x, cy: pos.y, r: 10,
          fill: "#09263b", stroke: routeColor, "stroke-width": 1.8}))
        layer.appendChild(element("text", {x: pos.x, y: pos.y + 3.5,
          fill: routeColor, "font-size": 10, "text-anchor": "middle",
          "font-family": "monospace"}, String(index + 1)))
        previous = point
      }
    }
    for (const entity of this.getEntities().values()) {
      if (entity.status === "destroyed" || !entity.render) continue
      const p = projection.point(entity.render)
      const ownEntity = entity.id === this.getSelfId()
      const hex = ownEntity ? "#6ff5ff" : entity.kind === "npc" ? "#ffad76" : "#c6b0ff"
      layer.appendChild(element("circle", {cx: p.x, cy: p.y, r: ownEntity ? 6 : 4,
        fill: hex, opacity: 0.93}))
      if (ownEntity) {
        layer.appendChild(element("circle", {cx: p.x, cy: p.y, r: 11,
          fill: "none", stroke: hex, "stroke-width": 1.5}))
      }
    }
  }
}
