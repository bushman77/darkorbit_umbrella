export const DEFAULT_COMMAND_INTERVAL_MS = 100
export const DEFAULT_DESTINATION_EPSILON = 2
export const DEFAULT_SHIP_DEAD_ZONE = 28

const distanceSquared = (left, right) => {
  const deltaX = left.x - right.x
  const deltaY = left.y - right.y
  return deltaX * deltaX + deltaY * deltaY
}

const validPoint = point => point && Number.isFinite(point.x) && Number.isFinite(point.y)

export class PointerNavigation {
  constructor({
    canvas,
    destinationForPointer,
    shipPosition,
    sendDestination,
    windowTarget = globalThis.window,
    documentTarget = globalThis.document,
    now = () => performance.now(),
    setTimer = (callback, delay) => windowTarget.setTimeout(callback, delay),
    clearTimer = timer => windowTarget.clearTimeout(timer),
    commandIntervalMs = DEFAULT_COMMAND_INTERVAL_MS,
    destinationEpsilon = DEFAULT_DESTINATION_EPSILON,
    shipDeadZone = DEFAULT_SHIP_DEAD_ZONE,
  }) {
    this.canvas = canvas
    this.destinationForPointer = destinationForPointer
    this.shipPosition = shipPosition
    this.sendDestination = sendDestination
    this.windowTarget = windowTarget
    this.documentTarget = documentTarget
    this.now = now
    this.setTimer = setTimer
    this.clearTimer = clearTimer
    this.commandIntervalMs = commandIntervalMs
    this.destinationEpsilonSquared = destinationEpsilon * destinationEpsilon
    this.shipDeadZoneSquared = shipDeadZone * shipDeadZone

    this.pointerId = null
    this.pointer = null
    this.pending = false
    this.pendingClick = false
    this.timer = null
    this.lastSentAt = -Infinity
    this.lastDestination = null

    this.onPointerDown = event => this.handlePointerDown(event)
    this.onPointerMove = event => this.handlePointerMove(event)
    this.onPointerUp = event => this.handlePointerUp(event)
    this.onPointerCancel = event => this.handlePointerCancel(event)
    this.onLostPointerCapture = event => this.handleLostPointerCapture(event)
    this.onWindowBlur = () => this.cancel()
    this.onVisibilityChange = () => {
      if (this.documentTarget.hidden) this.cancel()
    }
  }

  attach() {
    this.canvas.addEventListener("pointerdown", this.onPointerDown)
    this.canvas.addEventListener("pointermove", this.onPointerMove)
    this.canvas.addEventListener("pointerup", this.onPointerUp)
    this.canvas.addEventListener("pointercancel", this.onPointerCancel)
    this.canvas.addEventListener("lostpointercapture", this.onLostPointerCapture)
    this.windowTarget.addEventListener("pointerup", this.onPointerUp)
    this.windowTarget.addEventListener("pointercancel", this.onPointerCancel)
    this.windowTarget.addEventListener("blur", this.onWindowBlur)
    this.documentTarget.addEventListener("visibilitychange", this.onVisibilityChange)
    return this
  }

  destroy() {
    this.cancel()
    this.canvas.removeEventListener("pointerdown", this.onPointerDown)
    this.canvas.removeEventListener("pointermove", this.onPointerMove)
    this.canvas.removeEventListener("pointerup", this.onPointerUp)
    this.canvas.removeEventListener("pointercancel", this.onPointerCancel)
    this.canvas.removeEventListener("lostpointercapture", this.onLostPointerCapture)
    this.windowTarget.removeEventListener("pointerup", this.onPointerUp)
    this.windowTarget.removeEventListener("pointercancel", this.onPointerCancel)
    this.windowTarget.removeEventListener("blur", this.onWindowBlur)
    this.documentTarget.removeEventListener("visibilitychange", this.onVisibilityChange)
  }

  handlePointerDown(event) {
    if (event.button !== 0 || this.pointerId !== null) return

    this.pointerId = event.pointerId
    this.pointer = this.pointerFrom(event)
    event.preventDefault()

    try {
      this.canvas.setPointerCapture(event.pointerId)
    } catch (_error) {
      // Window-level release handlers still terminate navigation if capture is unavailable.
    }

    this.requestRetarget(true)
  }

  handlePointerMove(event) {
    if (event.pointerId !== this.pointerId) return

    if ((event.buttons & 1) === 0) {
      this.finishPointer(event.pointerId, false)
      return
    }

    this.pointer = this.pointerFrom(event)
    this.requestRetarget(false)
  }

  handlePointerUp(event) {
    if (event.pointerId === this.pointerId) this.finishPointer(event.pointerId, true)
  }

  handlePointerCancel(event) {
    if (event.pointerId === this.pointerId) this.finishPointer(event.pointerId, false)
  }

  handleLostPointerCapture(event) {
    if (event.pointerId === this.pointerId) this.finishPointer(event.pointerId, false)
  }

  cancel() {
    if (this.pointerId !== null) this.releasePointerCapture(this.pointerId)
    this.pointerId = null
    this.pointer = null
    this.pending = false
    this.pendingClick = false
    this.clearScheduledRetarget()
  }

  finishPointer(pointerId, completeClick) {
    this.pointerId = null
    this.releasePointerCapture(pointerId)

    if (completeClick && this.pending) {
      this.flush()
      return
    }

    this.pointer = null
    this.pending = false
    this.pendingClick = false
    this.clearScheduledRetarget()
  }

  releasePointerCapture(pointerId) {
    try {
      if (!this.canvas.hasPointerCapture || this.canvas.hasPointerCapture(pointerId)) {
        this.canvas.releasePointerCapture(pointerId)
      }
    } catch (_error) {
      // Capture may already have been released by the browser.
    }
  }

  requestRetarget(click = false) {
    this.pending = true
    this.pendingClick ||= click
    this.flush()
  }

  flush() {
    if (!this.pending || !this.pointer) return

    const elapsed = this.now() - this.lastSentAt
    if (elapsed < this.commandIntervalMs) {
      this.scheduleRetarget(this.commandIntervalMs - elapsed)
      return
    }

    this.clearScheduledRetarget()

    const destination = this.destinationForPointer(this.pointer)
    const allowShipDeadZone = this.pendingClick
    this.pending = false
    this.pendingClick = false

    if (validPoint(destination) && !this.redundantDestination(destination)) {
      const ship = this.shipPosition()
      const insideShipDeadZone = validPoint(ship) && distanceSquared(destination, ship) < this.shipDeadZoneSquared

      if (allowShipDeadZone || !insideShipDeadZone) {
        const accepted = this.sendDestination({...destination})
        if (accepted !== false) {
          this.lastDestination = {...destination}
          this.lastSentAt = this.now()
        }
      }
    }

    if (this.pointerId !== null) {
      this.scheduleRetarget(this.commandIntervalMs)
    } else {
      this.pointer = null
    }
  }

  scheduleRetarget(delay) {
    if (this.timer !== null) return

    this.timer = this.setTimer(() => {
      this.timer = null
      if (this.pointerId !== null) this.pending = true
      this.flush()
    }, Math.max(0, delay))
  }

  clearScheduledRetarget() {
    if (this.timer === null) return
    this.clearTimer(this.timer)
    this.timer = null
  }

  redundantDestination(destination) {
    return this.lastDestination &&
      distanceSquared(destination, this.lastDestination) < this.destinationEpsilonSquared
  }

  pointerFrom(event) {
    return {clientX: event.clientX, clientY: event.clientY}
  }
}
