// Optional pointer-locked cockpit steering. Only yaw/pitch come from the
// mouse; throttle, roll, weapons, physics and network ownership stay separate.
export const MOUSE_STEERING_IDLE_MS = 180
export const MOUSE_STEERING_DEFAULT_SENSITIVITY = 1

const clamp = (value, low, high) => Math.min(high, Math.max(low, value))
export const validMouseSensitivity = value => Number.isFinite(value) &&
  value >= 0.4 && value <= 2.0

export function mouseSteeringAxes(movementX, movementY, sensitivity = 1) {
  const factor = validMouseSensitivity(sensitivity) ? sensitivity : 1
  const yaw = clamp((Number(movementX) || 0) * factor / 22, -1, 1)
  // Browser Y increases downwards. Moving the mouse UP pitches nose UP.
  const pitch = clamp(-(Number(movementY) || 0) * factor / 22, -1, 1)
  return {
    yaw: Math.abs(yaw) < 0.015 ? 0 : yaw,
    pitch: Math.abs(pitch) < 0.015 ? 0 : pitch,
  }
}

// Pure axis controller for testable time-bounded look input. No DOM/side effects.
// The caller is responsible for locking the pointer and pushing the resulting
// yaw/pitch to FlightControls; each movement replaces, not accumulates, intent.
export class MouseSteering {
  constructor({now = () => performance.now(), sensitivity = 1} = {}) {
    this.now = now
    this.sensitivity = validMouseSensitivity(sensitivity) ? sensitivity : 1
    this.yaw = 0
    this.pitch = 0
    this.lastMovementAt = -Infinity
  }

  move(deltaX, deltaY) {
    const {yaw, pitch} = mouseSteeringAxes(deltaX, deltaY, this.sensitivity)
    this.yaw = yaw
    this.pitch = pitch
    this.lastMovementAt = this.now()
    return this.axes()
  }

  axes() { return {yaw: this.yaw, pitch: this.pitch} }

  expire(time = this.now()) {
    if (time - this.lastMovementAt < MOUSE_STEERING_IDLE_MS) return null
    if (this.yaw === 0 && this.pitch === 0) return null
    this.yaw = 0
    this.pitch = 0
    return this.axes()
  }

  release() {
    this.yaw = 0
    this.pitch = 0
    this.lastMovementAt = -Infinity
    return this.axes()
  }
}
