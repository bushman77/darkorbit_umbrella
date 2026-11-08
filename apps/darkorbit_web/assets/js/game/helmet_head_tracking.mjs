// Three-degree-of-freedom handset head tracking; strictly local to the HMD.
// Euler YXZ and screen-orientation correction follow DeviceOrientationControls,
// then calibration makes the current pose the forward-looking baseline.
// No position, flight input, sensor telemetry or network request is produced.
const RADIANS = Math.PI / 180
const HALF_SQRT = Math.SQRT1_2
const INITIAL = Object.freeze({x: 0, y: 0, z: 0, w: 1})

const product = (a, b) => ({
  x: a.x*b.w + a.w*b.x + a.y*b.z - a.z*b.y,
  y: a.y*b.w + a.w*b.y + a.z*b.x - a.x*b.z,
  z: a.z*b.w + a.w*b.z + a.x*b.y - a.y*b.x,
  w: a.w*b.w - a.x*b.x - a.y*b.y - a.z*b.z,
})
const inverseUnit = q => ({x: -q.x, y: -q.y, z: -q.z, w: q.w})
const eulerYXZ = (x, y, z) => {
  const c1=Math.cos(x/2), c2=Math.cos(y/2), c3=Math.cos(z/2)
  const s1=Math.sin(x/2), s2=Math.sin(y/2), s3=Math.sin(z/2)
  return {
    x: s1*c2*c3 + c1*s2*s3,
    y: c1*s2*c3 - s1*c2*s3,
    z: c1*c2*s3 - s1*s2*c3,
    w: c1*c2*c3 + s1*s2*s3,
  }
}
export function handsetQuaternion({alpha, beta, gamma}, screenAngle = 0) {
  if (![alpha, beta, gamma, screenAngle].every(Number.isFinite)) return null
  // Convert the device's camera-up convention into Three.js' -Z view axis.
  const q = eulerYXZ(beta*RADIANS, alpha*RADIANS, -gamma*RADIANS)
  const phone = {x: -HALF_SQRT, y: 0, z: 0, w: HALF_SQRT}
  const a = -screenAngle * RADIANS / 2
  return product(product(q, phone), {x: 0, y: 0, z: Math.sin(a), w: Math.cos(a)})
}

export class HelmetHeadTracking {
  constructor({win = typeof window !== "undefined" ? window : null,
               now = () => performance.now(), onStatus = () => {}} = {}) {
    this.win = win
    this.now = now
    this.onStatus = onStatus
    this.enabled = false
    this.status = "off"
    this.last = null
    this.baseline = null
    this.lastAt = -Infinity
    this.onOrientation = event => {
      if (!this.enabled) return
      const screenAngle = Number(this.win?.screen?.orientation?.angle ??
        this.win?.orientation ?? 0)
      const q = handsetQuaternion(event, screenAngle)
      if (!q) return
      this.last = q
      if (!this.baseline) this.baseline = q
      this.lastAt = this.now()
      if (this.status !== "tracking") this.setStatus("tracking")
    }
  }

  setStatus(status) {
    this.status = status
    this.onStatus(status)
  }

  // Call directly in a physical tap handler. Android Chrome usually has no
  // requestPermission(); platforms that do must receive its transient gesture.
  async startFromGesture() {
    if (this.enabled) return this.status
    if (!this.win?.isSecureContext) {
      this.setStatus("https-required")
      return this.status
    }
    const api = this.win.DeviceOrientationEvent
    if (!api) {
      this.setStatus("unsupported")
      return this.status
    }
    try {
      if (typeof api.requestPermission === "function") {
        const permission = await api.requestPermission()
        if (permission !== "granted") {
          this.setStatus("denied")
          return this.status
        }
      }
      this.win.addEventListener("deviceorientation", this.onOrientation)
      this.enabled = true
      this.setStatus("waiting")
    } catch (_error) {
      this.setStatus("denied")
    }
    return this.status
  }

  recenter() {
    if (!this.enabled || !this.last) return false
    this.baseline = {...this.last}
    return true
  }

  ready(time = this.now()) {
    return this.enabled && this.last !== null && this.baseline !== null &&
      time - this.lastAt < 2_000
  }

  rotation(time = this.now()) {
    if (!this.ready(time)) return null
    return product(inverseUnit(this.baseline), this.last)
  }

  stop() {
    if (this.enabled) this.win?.removeEventListener?.("deviceorientation", this.onOrientation)
    this.enabled = false
    this.last = null
    this.baseline = null
    this.lastAt = -Infinity
    this.setStatus("off")
  }
}

export const HEAD_NEUTRAL = INITIAL
