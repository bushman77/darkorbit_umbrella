// WASD space piloting; throttle is a signed setpoint in [-1, 1].
// The server owns orientation, position, velocity and thrust physics.
const ROTATION_KEYS = new Set([
  "KeyA", "KeyD", "ArrowUp", "ArrowDown", "KeyZ", "KeyC", "KeyX",
])
const THROTTLE_KEYS = new Set(["KeyW", "KeyS"])
const THROTTLE_INTERVAL_MS = 120

const typing = target => Boolean(target?.isContentEditable ||
  ["INPUT", "TEXTAREA", "SELECT"].includes(target?.tagName))

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
    return {
      yaw: axis("KeyD", "KeyA"),
      pitch: Math.max(-1, Math.min(1,
        axis("ArrowUp", "ArrowDown") + Number(this.pressed.has("KeyX")))),
      roll: axis("KeyC", "KeyZ"),
    }
  }

  payload() {
    return {throttle: this.throttle, mode: this.mode, ...this.axes()}
  }

  emit() {
    this.lastEmit = this.now()
    this.send(this.payload())
  }

  throttleDirection() {
    return Number(this.pressed.has("KeyW")) - Number(this.pressed.has("KeyS"))
  }

  stepThrottle(direction, time) {
    if (!direction || time - this.lastThrottleChange < THROTTLE_INTERVAL_MS) return false
    this.lastThrottleChange = time
    const next = Math.max(-1, Math.min(1, Math.round(
      (this.throttle + direction * 0.1) * 10) / 10))
    if (next === this.throttle) return false
    this.throttle = next
    this.emit()
    return true
  }

  keyDown(event) {
    if (event.defaultPrevented || typing(event.target) || !this.active()) return false

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
      this.stepThrottle(plus ? 1 : -1, this.now())
      return true
    }

    if (event.code === "KeyF") {
      event.preventDefault()
      if (this.pressed.size) {
        this.pressed.clear()
        this.emit()
      }
      return true
    }

    if (!THROTTLE_KEYS.has(event.code) && !ROTATION_KEYS.has(event.code)) return false
    event.preventDefault()
    if (!this.pressed.has(event.code)) {
      this.pressed.add(event.code)
      if (THROTTLE_KEYS.has(event.code)) {
        // Immediate response, then a time-based ramp while held.
        if (!this.stepThrottle(this.throttleDirection(), this.now())) this.emit()
      } else {
        this.emit()
      }
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

  release({silent = false} = {}) {
    if (!this.pressed.size) return
    this.pressed.clear()
    if (!silent) this.emit()
  }

  resetThrottle() {
    // Do not send controls after autopilot engages: that would cancel its route.
    this.throttle = 0
    this.pressed.clear()
  }

  heartbeat(time) {
    if (!this.active() || !this.pressed.size) return
    // W/S ramp the signed throttle while held, independent of OS key repeats.
    if (this.throttleDirection() !== 0) this.stepThrottle(this.throttleDirection(), time)
    if (time - this.lastEmit > 300) this.emit()
  }
}
