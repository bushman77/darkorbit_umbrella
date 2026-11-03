// Optional pointer-locked cockpit steering. Mouse input is an impulse on
// server-authoritative yaw/pitch; throttle, roll and weapons remain separate.
//
// Raw browser mousemove events arrive in uneven bursts (and may include 0,0).
// Accumulate nearby impulses, tolerate short input gaps, and smoothly ease
// back to neutral so turning doesn't abruptly stop after a single frame.
export const MOUSE_STEERING_IDLE_MS = 300
export const MOUSE_STEERING_DECAY_MS = 150
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
    this.lastDecayAt = -Infinity
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
    const carry = time - this.lastMovementAt <= 120 ? 0.5 : 0
    this.yaw = clamp(this.yaw * carry + yaw, -1, 1)
    this.pitch = clamp(this.pitch * carry + pitch, -1, 1)
    this.lastMovementAt = time
    this.lastDecayAt = -Infinity
    return this.axes()
  }

  axes() { return {yaw: this.yaw, pitch: this.pitch} }

  expire(time = this.now()) {
    if (time - this.lastMovementAt < MOUSE_STEERING_IDLE_MS) return null
    if (this.yaw === 0 && this.pitch === 0) return null

    // Decay after the grace period. This is called by the cockpit animation
    // loop, making mouse release independent of OS event packet frequency.
    const previous = this.lastDecayAt === -Infinity
      ? this.lastMovementAt + MOUSE_STEERING_IDLE_MS : this.lastDecayAt
    const dt = Math.max(0, time - previous)
    this.lastDecayAt = time
    const decay = Math.exp(-dt / MOUSE_STEERING_DECAY_MS)
    this.yaw *= decay
    this.pitch *= decay
    if (Math.abs(this.yaw) < 0.015) this.yaw = 0
    if (Math.abs(this.pitch) < 0.015) this.pitch = 0
    return this.axes()
  }

  release() {
    this.yaw = 0
    this.pitch = 0
    this.lastMovementAt = -Infinity
    this.lastDecayAt = -Infinity
    return this.axes()
  }
}
