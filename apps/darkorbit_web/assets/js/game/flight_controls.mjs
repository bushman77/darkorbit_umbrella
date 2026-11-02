// Six-key flight attitude plus +/- throttle; signed setpoint in [-1, 1].
// The server owns orientation, position, velocity and thrust physics.
const ROTATION_KEYS = new Set(["KeyW", "KeyS", "KeyA", "KeyD", "KeyQ", "KeyE"])
const THROTTLE_KEYS = new Set(["Equal", "Minus", "NumpadAdd", "NumpadSubtract"])
const THROTTLE_INTERVAL_MS = 120

const typing = target => Boolean(target?.isContentEditable ||
  ["INPUT", "TEXTAREA", "SELECT"].includes(target?.tagName))

export class FlightControls {
  constructor({send, active = () => true, now = () => performance.now()}) {
    this.send = send
    this.active = active
    this.now = now
    this.pressed = new Set()
    // If both pitch keys are registered (e.g., rapid direction reversal),
    // the most recently pressed pitch key commands the nose.
    this.lastPitchKey = null
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
      pitch: this.pressed.has("KeyW") && this.pressed.has("KeyS")
        ? (this.lastPitchKey === "KeyS" ? -1 : 1)
        : axis("KeyW", "KeyS"),
      roll: axis("KeyE", "KeyQ"),
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
    return Number(this.pressed.has("Equal") || this.pressed.has("NumpadAdd")) -
      Number(this.pressed.has("Minus") || this.pressed.has("NumpadSubtract"))
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

    if (event.code === "KeyF") {
      event.preventDefault()
      let changed = false
      for (const code of ROTATION_KEYS) changed = this.pressed.delete(code) || changed
      if (changed) {
        this.lastPitchKey = null
        this.emit()
      }
      return true
    }

    if (!THROTTLE_KEYS.has(event.code) && !ROTATION_KEYS.has(event.code)) return false
    event.preventDefault()
    if (!this.pressed.has(event.code)) {
      this.pressed.add(event.code)
      if (event.code === "KeyW" || event.code === "KeyS") this.lastPitchKey = event.code
      if (THROTTLE_KEYS.has(event.code)) {
        // One immediate 10% step, then a time-based ramp while held.
        // Browser key-repeat does not change the ramp rate.
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
    if (event.code === this.lastPitchKey) {
      const other = event.code === "KeyW" ? "KeyS" : "KeyW"
      this.lastPitchKey = this.pressed.has(other) ? other : null
    }
    this.emit()
    return true
  }

  release({silent = false} = {}) {
    if (!this.pressed.size) return
    this.pressed.clear()
    this.lastPitchKey = null
    if (!silent) this.emit()
  }

  resetThrottle() {
    // Do not send controls after autopilot engages: that would cancel its route.
    this.throttle = 0
    this.pressed.clear()
    this.lastPitchKey = null
  }

  heartbeat(time) {
    if (!this.active() || !this.pressed.size) return
    // =/- ramp the signed throttle while held, independent of OS key repeats.
    if (this.throttleDirection() !== 0) this.stepThrottle(this.throttleDirection(), time)
    if (time - this.lastEmit > 300) this.emit()
  }
}
