const DIRECTIONS = Object.freeze({
  KeyA: ["yaw", -1], KeyD: ["yaw", 1],
  KeyW: ["pitch", -1], KeyX: ["pitch", 1],
  KeyZ: ["roll", -1], KeyC: ["roll", 1],
})

const isTyping = target => Boolean(target?.isContentEditable ||
  ["INPUT", "TEXTAREA", "SELECT"].includes(target?.tagName))

// Only user intent crosses the socket. Position, velocity, acceleration,
// rotation angles and speed limits remain authoritative in Core.World.
export class FlightControls {
  constructor({send, active = () => true, now = () => performance.now()}) {
    this.send = send
    this.active = active
    this.now = now
    this.pressed = new Set()
    this.throttle = 0
    this.mode = "cruise"
    this.lastEmit = -Infinity
    this.lastThrottleChange = -Infinity
  }

  axes() {
    const axis = (positive, negative) =>
      Number(this.pressed.has(positive)) - Number(this.pressed.has(negative))
    return {yaw: axis("KeyD", "KeyA"), pitch: axis("KeyX", "KeyW"), roll: axis("KeyC", "KeyZ")}
  }

  payload() {
    return {throttle: this.throttle, mode: this.mode, ...this.axes()}
  }

  emit() {
    this.lastEmit = this.now()
    this.send(this.payload())
  }

  keyDown(event) {
    if (event.defaultPrevented || isTyping(event.target) || !this.active()) return false

    if (event.code === "KeyE" && event.ctrlKey && !event.altKey && !event.metaKey && !event.shiftKey) {
      event.preventDefault()
      if (!event.repeat) {
        this.mode = this.mode === "cruise" ? "newtonian" : "cruise"
        this.emit()
      }
      return true
    }

    if (event.altKey || event.ctrlKey || event.metaKey ||
        (event.shiftKey && event.code !== "Equal")) return false

    const plus = ["Equal", "NumpadAdd"].includes(event.code)
    const minus = ["Minus", "NumpadSubtract"].includes(event.code)
    if (plus || minus) {
      event.preventDefault()
      const time = this.now()
      if (time - this.lastThrottleChange >= 90) {
        this.lastThrottleChange = time
        this.throttle = Math.max(-1, Math.min(1, Math.round(
          (this.throttle + (plus ? 0.1 : -0.1)) * 10) / 10))
        this.emit()
      }
      return true
    }

    if (event.code === "KeyS") {
      event.preventDefault()
      if (this.pressed.size) {
        this.pressed.clear()
        this.emit()
      }
      return true
    }

    if (!Object.hasOwn(DIRECTIONS, event.code)) return false
    event.preventDefault()
    if (!this.pressed.has(event.code)) {
      this.pressed.add(event.code)
      this.emit()
    }
    return true
  }

  keyUp(event) {
    if (!this.pressed.has(event.code)) return false
    event.preventDefault()
    this.pressed.delete(event.code)
    this.emit()
    return true
  }

  release() {
    if (!this.pressed.size) return
    this.pressed.clear()
    this.emit()
  }

  resetThrottle() {
    // Autopilot owns movement now. Do not transmit while resetting local
    // controls; a new flight_controls message would cancel the new route.
    this.throttle = 0
    this.pressed.clear()
  }

  heartbeat(time) {
    if (!this.active() || !this.pressed.size) return
    if (time - this.lastEmit > 300) this.emit()
  }
}
