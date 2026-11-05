// Android browsers can dim or suspend WebGL and Phoenix when the display
// sleeps. Request a Screen Wake Lock from the headset user's direct tap.
// This is best effort: HTTPS, browser support and device power policy apply.
// Wake locks are not authentication tokens and do not bypass session security.
export class HelmetScreenWake {
  constructor({wakeLock, visible, schedule} = {}) {
    this.api = wakeLock === undefined
      ? (typeof navigator !== "undefined" ? navigator.wakeLock : null) : wakeLock
    this.visible = visible || (() => typeof document === "undefined" || !document.hidden)
    this.schedule = schedule || ((callback, delay) => setTimeout(callback, delay))
    this.active = false
    this.sentinel = null
    this.pending = null
    this.retryCount = 0
  }

  enable() {
    this.active = true
    this.retryCount = 0
    return this.acquire()
  }

  async acquire() {
    if (!this.active || !this.visible() || !this.api?.request) return false
    if (this.sentinel && !this.sentinel.released) return true
    if (this.pending) return this.pending

    this.pending = Promise.resolve()
      .then(() => this.api.request("screen"))
      .then(sentinel => {
        if (!this.active || !this.visible()) {
          Promise.resolve(sentinel.release?.()).catch(() => {})
          return false
        }
        this.sentinel = sentinel
        sentinel.addEventListener?.("release", () => {
          if (this.sentinel !== sentinel) return
          this.sentinel = null
          // A transient Android/browser release can be retried, but never
          // spin continuously if the OS revokes wake locks for battery safety.
          if (this.active && this.visible() && this.retryCount < 2) {
            this.retryCount++
            this.schedule(() => { if (this.active) this.acquire() }, 3000)
          }
        })
        return true
      })
      .catch(() => false)
      .finally(() => { this.pending = null })
    return this.pending
  }

  async onVisibilityChange() {
    if (this.visible()) {
      this.retryCount = 0
      return this.acquire()
    }
    const sentinel = this.sentinel
    this.sentinel = null
    if (sentinel) {
      try { await sentinel.release?.() } catch (_error) { /* OS already released */ }
    }
    return false
  }

  async disable() {
    this.active = false
    const sentinel = this.sentinel
    this.sentinel = null
    if (sentinel) {
      try { await sentinel.release?.() } catch (_error) { /* already released */ }
    }
  }
}
