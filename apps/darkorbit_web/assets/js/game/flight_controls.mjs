// Six-key flight attitude plus mouse-wheel target throttle in [-1, 1].
// Ctrl+wheel emits a short, spring-return ship-roll intention.
// The server owns orientation, position, velocity and thrust physics.
const ROTATION_KEYS = new Set(["KeyW", "KeyS", "KeyA", "KeyD", "KeyQ", "KeyE"])
const THROTTLE_KEYS = new Set(["Equal", "Minus", "NumpadAdd", "NumpadSubtract"])
const THROTTLE_INTERVAL_MS = 120
const WHEEL_THRESHOLD_PX = 80
const WHEEL_STEP = 0.05
const ROLL_PULSE_MS = 320
const ROLL_EXTENSION_MS = 170
const MAX_ROLL_PULSE_MS = 700

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
    this.wheelAccumulated = 0
    this.lastWheelAt = -Infinity
    this.wheelRollAccumulated = 0
    this.lastRollWheelAt = -Infinity
    this.wheelRollDirection = 0
    this.wheelRollUntil = -Infinity
    this.mouseAxes = {yaw: 0, pitch: 0}
    this.mouseMode = false
    this.mouseDirty = false
    this.lastMouseEmit = -Infinity
  }

  axes() {
    const axis = (positive, negative) =>
      Number(this.pressed.has(positive)) - Number(this.pressed.has(negative))
    return {
      yaw: axis("KeyD", "KeyA") || this.mouseAxes.yaw,
      pitch: (this.pressed.has("KeyW") && this.pressed.has("KeyS")
        ? (this.lastPitchKey === "KeyS" ? -1 : 1)
        : axis("KeyW", "KeyS")) || this.mouseAxes.pitch,
      // Keyboard roll wins if Q/E is held. Ctrl+wheel provides a short pulse
      // that springs back to neutral; it never latches a permanent roll.
      roll: axis("KeyE", "KeyQ") ||
        (this.now() < this.wheelRollUntil ? this.wheelRollDirection : 0),
    }
  }

  payload() {
    return {throttle: this.throttle, mode: this.mode,
      mouse_steering: this.mouseMode, ...this.axes()}
  }

  emit() {
    this.lastEmit = this.now()
    this.send(this.payload())
  }

  // Only actual pointer capture enables the server's faster, bounded
  // mouse turn profile. Keyboard-only flight keeps its original rates.
  setMouseMode(enabled, {silent = false} = {}) {
    const next = enabled === true
    if (this.mouseMode === next) return false
    this.mouseMode = next
    if (!next) {
      this.mouseAxes = {yaw: 0, pitch: 0}
      this.mouseDirty = false
    }
    if (!silent && this.active()) this.emit()
    return true
  }

  setMouseSteering({yaw = 0, pitch = 0} = {}) {
    if (!this.active()) return false
    const clamp = value => Math.max(-1, Math.min(1, Number.isFinite(value) ? value : 0))
    yaw = clamp(yaw)
    pitch = clamp(pitch)
    if (this.mouseAxes.yaw === yaw && this.mouseAxes.pitch === pitch) return false
    this.mouseAxes = {yaw, pitch}
    this.mouseDirty = true
    const now = this.now()
    if (now - this.lastMouseEmit >= 50) {
      this.emit()
      this.lastMouseEmit = now
      this.mouseDirty = false
    }
    return true
  }

  clearMouseSteering({silent = false} = {}) {
    const changed = this.mouseAxes.yaw !== 0 || this.mouseAxes.pitch !== 0
    this.mouseAxes = {yaw: 0, pitch: 0}
    this.mouseDirty = false
    if (changed && !silent) this.emit()
    return changed
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

  wheel(event) {
    if (event.defaultPrevented || typing(event.target) || !this.active() ||
        event.altKey || event.metaKey || event.shiftKey ||
        !Number.isFinite(event.deltaY) || event.deltaY === 0) return false

    // The listener belongs to the flight canvas and is non-passive, so we
    // can prevent both browser scrolling and Ctrl+wheel page zoom there.
    event.preventDefault()
    const now = this.now()
    const pixels = event.deltaY * (event.deltaMode === 1 ? 40 : event.deltaMode === 2 ? 800 : 1)
    const cappedPixels = Math.max(-240, Math.min(240, pixels))

    if (event.ctrlKey) {
      // Scrolling UP rolls right (E direction); DOWN rolls left (Q direction).
      // This accumulator is separate from throttle, so swapping the Ctrl
      // modifier cannot accidentally alter the commanded target speed.
      if (now - this.lastRollWheelAt > 250 ||
          Math.sign(cappedPixels) !== Math.sign(this.wheelRollAccumulated)) {
        this.wheelRollAccumulated = 0
      }
      this.lastRollWheelAt = now
      this.wheelRollAccumulated += cappedPixels
      const steps = Math.min(3, Math.floor(Math.abs(this.wheelRollAccumulated) / WHEEL_THRESHOLD_PX))
      if (!steps) return true

      const direction = -Math.sign(this.wheelRollAccumulated)
      this.wheelRollAccumulated -= Math.sign(this.wheelRollAccumulated) *
        steps * WHEEL_THRESHOLD_PX
      const remaining = direction === this.wheelRollDirection
        ? Math.max(0, this.wheelRollUntil - now) : 0
      this.wheelRollDirection = direction
      // Every deliberate notch causes a finite roll; repeated notches
      // extend the command within a safe bound rather than locking it on.
      this.wheelRollUntil = now + Math.min(MAX_ROLL_PULSE_MS,
        Math.max(ROLL_PULSE_MS, remaining + ROLL_EXTENSION_MS * steps))
      this.emit()
      return true
    }

    // Unmodified wheel selects target speed. No roll state is modified.
    if (now - this.lastWheelAt > 250 || Math.sign(pixels) !== Math.sign(this.wheelAccumulated)) {
      this.wheelAccumulated = 0
    }
    this.lastWheelAt = now
    this.wheelAccumulated += cappedPixels
    const steps = Math.min(3, Math.floor(Math.abs(this.wheelAccumulated) / WHEEL_THRESHOLD_PX))
    if (steps === 0) return true

    const direction = -Math.sign(this.wheelAccumulated)
    this.wheelAccumulated -= Math.sign(this.wheelAccumulated) * steps * WHEEL_THRESHOLD_PX
    const next = Math.max(-1, Math.min(1,
      Math.round((this.throttle + direction * WHEEL_STEP * steps) * 100) / 100))
    if (next !== this.throttle) {
      this.throttle = next
      this.emit()
    }
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
      let changed = this.wheelRollDirection !== 0 ||
        this.mouseAxes.yaw !== 0 || this.mouseAxes.pitch !== 0
      for (const code of ROTATION_KEYS) changed = this.pressed.delete(code) || changed
      this.clearWheelRoll()
      this.clearMouseSteering({silent: true})
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

  clearWheelRoll() {
    this.wheelRollDirection = 0
    this.wheelRollUntil = -Infinity
    this.wheelRollAccumulated = 0
  }

  release({silent = false} = {}) {
    if (!this.pressed.size && !this.wheelRollDirection && !this.mouseMode &&
        this.mouseAxes.yaw === 0 && this.mouseAxes.pitch === 0) return
    this.pressed.clear()
    this.lastPitchKey = null
    this.clearWheelRoll()
    this.clearMouseSteering({silent: true})
    this.setMouseMode(false, {silent: true})
    if (!silent) this.emit()
  }

  resetThrottle() {
    // Do not send controls after autopilot engages: that would cancel its route.
    this.throttle = 0
    this.pressed.clear()
    this.lastPitchKey = null
    this.wheelAccumulated = 0
    this.clearWheelRoll()
    this.clearMouseSteering({silent: true})
    this.setMouseMode(false, {silent: true})
  }

  heartbeat(time) {
    if (!this.active()) return
    if (this.mouseDirty && time - this.lastMouseEmit >= 50) {
      this.emit()
      this.lastMouseEmit = time
      this.mouseDirty = false
    }
    // Always send a neutral roll intention when the wheel impulse expires,
    // even if no keyboard button is held. Otherwise the server could keep
    // rolling until its own input-expiry watchdog trips.
    if (this.wheelRollDirection && time >= this.wheelRollUntil) {
      this.clearWheelRoll()
      this.emit()
    }
    if (!this.pressed.size && !this.wheelRollDirection &&
        this.mouseAxes.yaw === 0 && this.mouseAxes.pitch === 0) return
    // =/- ramp the signed throttle while held, independent of OS key repeats.
    if (this.throttleDirection() !== 0) this.stepThrottle(this.throttleDirection(), time)
    if (time - this.lastEmit > 300) this.emit()
  }
}
