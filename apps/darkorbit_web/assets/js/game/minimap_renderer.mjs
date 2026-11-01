export const MINIMAP_FRAME_INTERVAL_MS = 50

const positive = value => Number.isFinite(Number(value)) && Number(value) > 0

export const minimapProjection = (boundaries, viewport, padding = 10) => {
  if (!positive(boundaries?.width) || !positive(boundaries?.height)) return null

  const availableWidth = Math.max(1, viewport.width - padding * 2)
  const availableHeight = Math.max(1, viewport.height - padding * 2)
  const scale = Math.min(availableWidth / boundaries.width, availableHeight / boundaries.height)
  const width = boundaries.width * scale
  const height = boundaries.height * scale

  return {
    x: (viewport.width - width) / 2,
    y: (viewport.height - height) / 2,
    width,
    height,
    point(position) {
      return {
        x: this.x + (position.x / boundaries.width) * this.width,
        y: this.y + (position.y / boundaries.height) * this.height,
      }
    },
  }
}

export class MinimapRenderer {
  constructor({
    canvas,
    getEntities,
    getBoundaries,
    getSelfId,
    getDevicePixelRatio = () => globalThis.window?.devicePixelRatio || 1,
    resizeObserverFactory = callback => new ResizeObserver(callback),
  }) {
    this.canvas = canvas
    this.getEntities = getEntities
    this.getBoundaries = getBoundaries
    this.getSelfId = getSelfId
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

    const selfId = String(this.getSelfId())
    for (const entity of this.getEntities()) {
      if (!entity?.render || entity.status === "destroyed") continue
      const point = projection.point(entity.render)
      const isSelf = String(entity.id) === selfId
      context.fillStyle = entity.kind === "npc" ? "#fb923c" : isSelf ? "#67e8f9" : "#c4b5fd"
      context.beginPath()
      context.arc(point.x, point.y, isSelf ? 3 : 2.25, 0, Math.PI * 2)
      context.fill()
    }

    this.lastDrawAt = time
    return true
  }
}
