// Gaze selection for an opt-in HMD. One second to arm the chosen target,
// followed by a circular 800 ms confirmation animation. Changing or leaving
// the target resets the timer; a held gaze cannot activate repeatedly.
export const GAZE_ARM_MS = 1_000
export const GAZE_CONFIRM_MS = 800

export class HelmetGazeDwell {
  constructor({armMs = GAZE_ARM_MS, confirmMs = GAZE_CONFIRM_MS} = {}) {
    this.armMs = armMs
    this.confirmMs = confirmMs
    this.reset()
  }
  reset() {
    this.target = null
    this.startedAt = 0
    this.fired = false
  }
  update(target, now, enabled = true) {
    if (!enabled || typeof target !== "string" || !target || !Number.isFinite(now)) {
      this.reset()
      return {target: null, armed: false, progress: 0, activated: null}
    }
    if (this.target !== target || now < this.startedAt) {
      this.target = target
      this.startedAt = now
      this.fired = false
    }
    const elapsed = Math.max(0, now - this.startedAt)
    const armed = elapsed >= this.armMs
    const progress = armed ?
      Math.min(1, (elapsed - this.armMs) / Math.max(1, this.confirmMs)) : 0
    const activated = !this.fired && progress >= 1 ? target : null
    if (activated) this.fired = true
    return {target, armed, progress, activated}
  }
}
