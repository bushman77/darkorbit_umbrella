// Desktop-only, bounded control intentions for an authenticated docked pilot.
// MapServer owns position, speed, collision and room changes; the phone only
// renders the replicated station pose and independently tracks head motion.
const keys = new Set(["KeyW", "KeyA", "KeyS", "KeyD", "ArrowLeft", "ArrowRight"])
export const stationAxes = held => ({
  forward: Number(held.has("KeyW")) - Number(held.has("KeyS")),
  strafe: Number(held.has("KeyD")) - Number(held.has("KeyA")),
  turn: Number(held.has("ArrowRight")) - Number(held.has("ArrowLeft")),
})

export class StationWalkingControls {
  constructor({active, sendWalk, sendLook, canvas, win = window}) {
    this.active = active
    this.sendWalk = sendWalk
    this.sendLook = sendLook
    this.canvas = canvas
    this.win = win
    this.held = new Set()
    this.sent = ""
    this.lastLookAt = -Infinity
    this.pendingLook = 0
  }

  start() {
    this.win.addEventListener("keydown", e => this.key(e, true), true)
    this.win.addEventListener("keyup", e => this.key(e, false), true)
    this.win.addEventListener("blur", () => this.release())
    this.win.document?.addEventListener("visibilitychange", () => {
      if (this.win.document.hidden) this.release()
    })
    this.canvas?.addEventListener("pointerdown", e => {
      if (this.active() && e.button === 0 &&
          this.win.document?.pointerLockElement !== this.canvas) {
        this.canvas.requestPointerLock?.()
      }
    })
    this.win.addEventListener("mousemove", e => {
      if (!this.active() || this.win.document?.pointerLockElement !== this.canvas) return
      const movement = Number(e.movementX) || 0
      if (!movement) return
      const now = this.win.performance?.now?.() ?? performance.now()
      this.pendingLook += movement * 0.0025
      if (now - this.lastLookAt >= 40) this.flushLook(now)
    })
    return this
  }

  flushLook(now) {
    if (Math.abs(this.pendingLook) < 0.00001) return
    const delta = Math.max(-0.35, Math.min(0.35, this.pendingLook))
    // Discard any excess instead of replaying old mouse motion on future
    // frames. The camera stops as soon as the pointer stops moving.
    this.pendingLook = 0
    this.lastLookAt = now
    this.sendLook({delta_yaw: delta})
  }

  key(e, down) {
    if (!keys.has(e.code) || !this.active()) return false
    if (e.target?.closest?.("input,textarea,select,[contenteditable='true']")) return false
    e.preventDefault?.()
    e.stopImmediatePropagation?.()
    if (down) this.held.add(e.code)
    else this.held.delete(e.code)
    this.emit()
    return true
  }

  emit() {
    const axes = stationAxes(this.held)
    const key = JSON.stringify(axes)
    if (key !== this.sent) {
      this.sent = key
      this.sendWalk(axes)
    }
  }

  release() {
    if (this.held.size || this.sent) {
      this.held.clear()
      this.sent = ""
      this.sendWalk(stationAxes(this.held))
    }
    this.pendingLook = 0
  }

  frame(now) {
    if (this.active() && now - this.lastLookAt >= 40) this.flushLook(now)
  }
}
