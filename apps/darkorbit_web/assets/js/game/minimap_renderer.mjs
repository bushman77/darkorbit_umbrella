export const MINIMAP_FRAME_INTERVAL_MS = 50
export const MINIMAP_POINTER_SLOP_PX = 8

const positive = value => Number.isFinite(Number(value)) && Number(value) > 0
const finitePoint = point =>
  point && Number.isFinite(Number(point.x)) && Number.isFinite(Number(point.y))
const clamp = (value, minimum, maximum) => Math.min(Math.max(value, minimum), maximum)

export const minimapProjection = (boundaries, viewport, padding = 10) => {
  if (
    !positive(boundaries?.width) ||
    !positive(boundaries?.height) ||
    !positive(viewport?.width) ||
    !positive(viewport?.height)
  ) return null

  const viewportWidth = Number(viewport.width)
  const viewportHeight = Number(viewport.height)
  const inset = Math.max(0, Number.isFinite(Number(padding)) ? Number(padding) : 0)
  const availableWidth = Math.max(1, viewportWidth - inset * 2)
  const availableHeight = Math.max(1, viewportHeight - inset * 2)
  const boundaryWidth = Number(boundaries.width)
  const boundaryHeight = Number(boundaries.height)
  const scale = Math.min(availableWidth / boundaryWidth, availableHeight / boundaryHeight)
  const width = boundaryWidth * scale
  const height = boundaryHeight * scale

  return {
    x: (viewportWidth - width) / 2,
    y: (viewportHeight - height) / 2,
    width,
    height,
    point(position) {
      return {
        x: this.x + (Number(position.x) / boundaryWidth) * this.width,
        y: this.y + (Number(position.y) / boundaryHeight) * this.height,
      }
    },
    worldPoint(position) {
      if (!finitePoint(position)) return null
      if (
        position.x < this.x ||
        position.x > this.x + this.width ||
        position.y < this.y ||
        position.y > this.y + this.height
      ) return null

      const x = ((position.x - this.x) / this.width) * boundaryWidth
      const y = ((position.y - this.y) / this.height) * boundaryHeight
      if (!Number.isFinite(x) || !Number.isFinite(y)) return null

      return {
        x: clamp(x, 0, boundaryWidth),
        y: clamp(y, 0, boundaryHeight),
      }
    },
  }
}

export const minimapWorldPoint = (pointer, canvas, boundaries, padding = 10) => {
  if (!finitePoint({x: pointer?.clientX, y: pointer?.clientY})) return null
  const rect = canvas?.getBoundingClientRect?.()
  const projection = minimapProjection(boundaries, rect, padding)
  if (!projection || !Number.isFinite(rect?.left) || !Number.isFinite(rect?.top)) return null

  return projection.worldPoint({
    x: Number(pointer.clientX) - rect.left,
    y: Number(pointer.clientY) - rect.top,
  })
}

export class MinimapNavigation {
  constructor({
    canvas,
    getBoundaries,
    sendDestination,
    canNavigate = () => true,
    windowTarget = globalThis.window,
    documentTarget = globalThis.document,
    pointerSlop = MINIMAP_POINTER_SLOP_PX,
  }) {
    this.canvas = canvas
    this.getBoundaries = getBoundaries
    this.sendDestination = sendDestination
    this.canNavigate = canNavigate
    this.windowTarget = windowTarget
    this.documentTarget = documentTarget
    this.pointerSlopSquared = pointerSlop * pointerSlop
    this.pointer = null

    this.onPointerDown = event => this.handlePointerDown(event)
    this.onPointerMove = event => this.handlePointerMove(event)
    this.onPointerUp = event => this.handlePointerUp(event)
    this.onPointerCancel = event => this.handlePointerCancel(event)
    this.onLostPointerCapture = event => this.handlePointerCancel(event)
    this.onContextMenu = event => this.handleContextMenu(event)
    this.onWindowBlur = () => this.cancel()
    this.onVisibilityChange = () => {
      if (this.documentTarget?.hidden) this.cancel()
    }
  }

  attach() {
    if (this.attached || !this.canvas?.addEventListener) return this
    this.attached = true
    this.canvas.addEventListener("pointerdown", this.onPointerDown)
    this.canvas.addEventListener("pointermove", this.onPointerMove)
    this.canvas.addEventListener("pointerup", this.onPointerUp)
    this.canvas.addEventListener("pointercancel", this.onPointerCancel)
    this.canvas.addEventListener("lostpointercapture", this.onLostPointerCapture)
    this.canvas.addEventListener("contextmenu", this.onContextMenu)
    this.windowTarget?.addEventListener?.("pointerup", this.onPointerUp)
    this.windowTarget?.addEventListener?.("pointercancel", this.onPointerCancel)
    this.windowTarget?.addEventListener?.("blur", this.onWindowBlur)
    this.documentTarget?.addEventListener?.("visibilitychange", this.onVisibilityChange)
    return this
  }

  destroy() {
    if (!this.attached) return
    this.cancel()
    this.canvas.removeEventListener("pointerdown", this.onPointerDown)
    this.canvas.removeEventListener("pointermove", this.onPointerMove)
    this.canvas.removeEventListener("pointerup", this.onPointerUp)
    this.canvas.removeEventListener("pointercancel", this.onPointerCancel)
    this.canvas.removeEventListener("lostpointercapture", this.onLostPointerCapture)
    this.canvas.removeEventListener("contextmenu", this.onContextMenu)
    this.windowTarget?.removeEventListener?.("pointerup", this.onPointerUp)
    this.windowTarget?.removeEventListener?.("pointercancel", this.onPointerCancel)
    this.windowTarget?.removeEventListener?.("blur", this.onWindowBlur)
    this.documentTarget?.removeEventListener?.("visibilitychange", this.onVisibilityChange)
    this.attached = false
  }

  handlePointerDown(event) {
    if (event.button !== 0 || this.pointer || !this.canNavigate()) return

    this.pointer = {
      id: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      moved: false,
    }
    this.canvas.classList?.add?.("is-navigating")

    if (event.pointerType !== "touch") {
      event.preventDefault()
      try {
        this.canvas.setPointerCapture?.(event.pointerId)
      } catch (_error) {
        // Window-level release handling still cleans up unavailable capture.
      }
    }
  }

  handlePointerMove(event) {
    if (!this.pointer || event.pointerId !== this.pointer.id) return
    const deltaX = event.clientX - this.pointer.startX
    const deltaY = event.clientY - this.pointer.startY
    if (deltaX * deltaX + deltaY * deltaY > this.pointerSlopSquared) {
      this.pointer.moved = true
      this.canvas.classList?.remove?.("is-navigating")
    }
  }

  handlePointerUp(event) {
    if (!this.pointer || event.pointerId !== this.pointer.id) return
    const completeClick = !this.pointer.moved && event.button === 0 && this.canNavigate()
    const pointerId = this.pointer.id
    this.pointer = null
    this.releasePointerCapture(pointerId)
    this.canvas.classList?.remove?.("is-navigating")

    if (!completeClick) return
    const destination = minimapWorldPoint(event, this.canvas, this.getBoundaries())
    if (!destination) return

    event.preventDefault()
    this.sendDestination({...destination})
  }

  handlePointerCancel(event) {
    if (this.pointer && event.pointerId === this.pointer.id) this.cancel()
  }

  handleContextMenu(event) {
    if (this.canNavigate()) event.preventDefault()
  }

  cancel() {
    if (this.pointer) this.releasePointerCapture(this.pointer.id)
    this.pointer = null
    this.canvas?.classList?.remove?.("is-navigating")
  }

  releasePointerCapture(pointerId) {
    try {
      if (!this.canvas.hasPointerCapture || this.canvas.hasPointerCapture(pointerId)) {
        this.canvas.releasePointerCapture?.(pointerId)
      }
    } catch (_error) {
      // Capture may already have been released by the browser.
    }
  }
}

export class MinimapRenderer {
  constructor({
    canvas,
    getEntities,
    getBoundaries,
    getSelfId,
    getDestination = () => null,
    getDevicePixelRatio = () => globalThis.window?.devicePixelRatio || 1,
    resizeObserverFactory = callback => new ResizeObserver(callback),
  }) {
    this.canvas = canvas
    this.getEntities = getEntities
    this.getBoundaries = getBoundaries
    this.getSelfId = getSelfId
    this.getDestination = getDestination
    this.getDevicePixelRatio = getDevicePixelRatio
    this.resizeObserverFactory = resizeObserverFactory
    this.lastDrawAt = -Infinity
    this.viewport = {width: 0, height: 0, dpr: 1}
  }

  start() {
    if (this.active || !this.canvas) return this
    this.context = this.canvas.getContext("2d")
    if (!this.context) return this
    this.active = true
    try {
      this.resizeObserver = this.resizeObserverFactory(() => this.resize())
      this.resizeObserver?.observe?.(this.canvas)
    } catch (_error) {
      this.resizeObserver = null
    }
    this.resize()
    return this
  }

  stop() {
    this.resizeObserver?.disconnect?.()
    this.resizeObserver = null
    this.active = false
  }

  resize() {
    if (!this.active) return false
    const rect = this.canvas.getBoundingClientRect()
    const width = Math.max(0, Math.floor(rect.width))
    const height = Math.max(0, Math.floor(rect.height))
    const dpr = Math.min(2, Math.max(1, Number(this.getDevicePixelRatio()) || 1))
    if (!width || !height) {
      this.viewport = {width, height, dpr}
      return false
    }

    const changed = width !== this.viewport.width ||
      height !== this.viewport.height ||
      dpr !== this.viewport.dpr
    this.viewport = {width, height, dpr}
    if (changed) {
      this.canvas.width = Math.max(1, Math.floor(width * dpr))
      this.canvas.height = Math.max(1, Math.floor(height * dpr))
    }
    return changed
  }

  draw(time, force = false) {
    if (!this.active || !this.context) return false
    if (!force && time - this.lastDrawAt < MINIMAP_FRAME_INTERVAL_MS) return false
    this.resize()
    if (!this.viewport.width || !this.viewport.height) return false

    const boundaries = this.getBoundaries()
    const projection = minimapProjection(boundaries, this.viewport)
    if (!projection) return false

    const context = this.context
    context.setTransform(this.viewport.dpr, 0, 0, this.viewport.dpr, 0, 0)
    context.clearRect(0, 0, this.viewport.width, this.viewport.height)
    context.fillStyle = "rgba(2, 8, 20, 0.96)"
    context.fillRect(0, 0, this.viewport.width, this.viewport.height)

    const gradient = context.createLinearGradient(0, 0, this.viewport.width, this.viewport.height)
    gradient.addColorStop(0, "rgba(8, 47, 73, 0.42)")
    gradient.addColorStop(1, "rgba(15, 23, 42, 0.08)")
    context.fillStyle = gradient
    context.fillRect(projection.x, projection.y, projection.width, projection.height)
    context.strokeStyle = "rgba(103, 232, 249, 0.62)"
    context.lineWidth = 1
    context.strokeRect(
      projection.x + 0.5,
      projection.y + 0.5,
      projection.width - 1,
      projection.height - 1
    )

    const entities = Array.from(this.getEntities() || [])
    const selfId = String(this.getSelfId())
    const self = entities.find(entity => String(entity?.id) === selfId)
    const destination = this.getDestination()
    if (finitePoint(self?.render) && finitePoint(destination)) {
      this.drawDestination(context, projection, self.render, destination, time)
    }

    for (const entity of entities) {
      if (!entity?.render || entity.status === "destroyed") continue
      const point = projection.point(entity.render)
      if (!finitePoint(point)) continue
      const isSelf = String(entity.id) === selfId
      context.fillStyle = entity.kind === "npc" ? "#fb923c" : isSelf ? "#67e8f9" : "#c4b5fd"
      context.beginPath()
      context.arc(point.x, point.y, isSelf ? 3 : 2.25, 0, Math.PI * 2)
      context.fill()

      if (isSelf) {
        context.strokeStyle = "rgba(207, 250, 254, 0.82)"
        context.lineWidth = 1
        context.beginPath()
        context.arc(point.x, point.y, 5, 0, Math.PI * 2)
        context.stroke()
      }
    }

    this.lastDrawAt = time
    return true
  }

  drawDestination(context, projection, player, destination, time) {
    const from = projection.point(player)
    const to = projection.point(destination)
    const pulse = 5 + (Math.sin(time * 0.008) + 1) * 1.25

    context.save()
    context.strokeStyle = "rgba(103, 232, 249, 0.34)"
    context.lineWidth = 1
    context.setLineDash([3, 4])
    context.beginPath()
    context.moveTo(from.x, from.y)
    context.lineTo(to.x, to.y)
    context.stroke()
    context.setLineDash([])

    context.strokeStyle = "rgba(165, 243, 252, 0.95)"
    context.lineWidth = 1.25
    context.beginPath()
    context.arc(to.x, to.y, pulse, 0, Math.PI * 2)
    context.moveTo(to.x - 3, to.y)
    context.lineTo(to.x + 3, to.y)
    context.moveTo(to.x, to.y - 3)
    context.lineTo(to.x, to.y + 3)
    context.stroke()
    context.restore()
  }
}
