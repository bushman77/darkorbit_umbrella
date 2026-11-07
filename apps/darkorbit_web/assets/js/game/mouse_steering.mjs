// Optional pointer-locked cockpit steering. Mouse input is an impulse on
// server-authoritative yaw/pitch; throttle, roll and weapons remain separate.
//
// The browser does not provide a "mouse stopped" event. Treat the lack of
// a nonzero movement packet for about one to two 60Hz frames as release.
// Preserve small-event accumulation while moving, but NEVER coast afterward.
export const MOUSE_STEERING_IDLE_MS = 25
export const MOUSE_STEERING_DEFAULT_SENSITIVITY = 1

const clamp = (value, low, high) => Math.min(high, Math.max(low, value))
export const validMouseSensitivity = value => Number.isFinite(value) &&
  value >= 0.4 && value <= 6.0

export function mouseSteeringAxes(movementX, movementY, sensitivity = 1) {
  const factor = validMouseSensitivity(sensitivity) ? sensitivity : 1
  const yaw = clamp((Number(movementX) || 0) * factor / 11, -1, 1)
  // Browser Y increases downwards. Moving mouse UP pitches nose UP.
  const pitch = clamp(-(Number(movementY) || 0) * factor / 11, -1, 1)
  return {
    yaw: Math.abs(yaw) < 0.015 ? 0 : yaw,
    pitch: Math.abs(pitch) < 0.015 ? 0 : pitch,
  }
}

export class MouseSteering {
  constructor({now = () => performance.now(), sensitivity = 1} = {}) {
    this.now = now
    this.sensitivity = validMouseSensitivity(sensitivity) ? sensitivity : 1
    this.yaw = 0
    this.pitch = 0
    this.lastMovementAt = -Infinity
  }

  move(deltaX, deltaY) {
    // Zero-delta events must not cancel the current movement or keep
    // resetting the idle clock. Browsers can generate many of these.
    if (!Number.isFinite(deltaX) || !Number.isFinite(deltaY) ||
        (deltaX === 0 && deltaY === 0)) return this.axes()

    const time = this.now()
    const {yaw, pitch} = mouseSteeringAxes(deltaX, deltaY, this.sensitivity)
    // Keep part of the previous neighboring impulse so a stream of small
    // movement events adds up to useful steering, rather than replacing the
    // input with the last 1px event.
    const adjacent = time - this.lastMovementAt < MOUSE_STEERING_IDLE_MS
    const carryYaw = adjacent && yaw !== 0 && Math.sign(yaw) === Math.sign(this.yaw)
      ? 0.5 : 0
    const carryPitch = adjacent && pitch !== 0 && Math.sign(pitch) === Math.sign(this.pitch)
      ? 0.5 : 0
    // Carry only while continuing the SAME axis/direction. Vertical-only
    // movement must not preserve old yaw, or vice versa.
    this.yaw = clamp(this.yaw * carryYaw + yaw, -1, 1)
    this.pitch = clamp(this.pitch * carryPitch + pitch, -1, 1)
    this.lastMovementAt = time
    return this.axes()
  }

  axes() { return {yaw: this.yaw, pitch: this.pitch} }

  expire(time = this.now()) {
    if (time - this.lastMovementAt < MOUSE_STEERING_IDLE_MS) return null
    if (this.yaw === 0 && this.pitch === 0) return null

    // One hard stop. Do not decay the last command over subsequent frames;
    // that looked like the cursor/ship continued moving after the hand stopped.
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
