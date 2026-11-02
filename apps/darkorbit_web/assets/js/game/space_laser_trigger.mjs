// Holding Space requests one manual shot whenever the world-owned weapon is
// ready. The client never computes hits, damage, heading or cooldown duration.
export class SpaceLaserTrigger {
  constructor({fire, active, worldTick, nextAttackTick, now = () => performance.now()}) {
    this.fire = fire
    this.active = active
    this.worldTick = worldTick
    this.nextAttackTick = nextAttackTick
    this.now = now
    this.held = false
    this.inFlight = false
    this.lastAttemptTick = -1
    this.retryAfter = -Infinity
  }

  press() {
    if (this.held) return
    this.held = true
    this.update(this.now())
  }

  release() {
    this.held = false
  }

  update(time) {
    if (!this.held || !this.active() || this.inFlight ||
        time < this.retryAfter) return false

    const tick = this.worldTick()
    if (!Number.isFinite(tick) || tick < this.nextAttackTick() ||
        tick <= this.lastAttemptTick) return false

    this.inFlight = true
    this.lastAttemptTick = tick
    this.fire((ok, reason) => {
      this.inFlight = false
      if (!ok) {
        // Throttle rejects rather than spamming the channel every tick.
        this.retryAfter = this.now() + (reason === "weapon_cooldown" ? 125 : 350)
      }
    })
    return true
  }
}
