// Rendering only. Server owns quaternion orientation; this module provides
// a shortest-arc, framerate-independent visual slerp and true heading info.
export const normalizeOrientation = q => {
  if (!q) return null
  const n = Math.hypot(q.x, q.y, q.z, q.w)
  if (!Number.isFinite(n) || n <= 0) return {x: 0, y: 0, z: 0, w: 1}
  return {x: q.x / n, y: q.y / n, z: q.z / n, w: q.w / n}
}

const dot = (a, b) => a.x*b.x + a.y*b.y + a.z*b.z + a.w*b.w
const clamp = n => Math.min(1, Math.max(-1, n))

export function smoothOrientation(current, target, deltaSeconds, settleSeconds = 0.085) {
  if (!target) return current || null
  if (!current) return normalizeOrientation(target)
  const from = normalizeOrientation(current)
  let to = normalizeOrientation(target)
  const elapsed = Math.max(0, Math.min(deltaSeconds, 0.15))
  const alpha = 1 - Math.exp(-elapsed / settleSeconds)
  if (alpha <= 0) return from

  let cosine = dot(from, to)
  if (cosine < 0) {
    to = {x: -to.x, y: -to.y, z: -to.z, w: -to.w}
    cosine = -cosine
  }
  let left, right
  if (cosine > 0.9995) {
    left = 1 - alpha
    right = alpha
  } else {
    const theta = Math.acos(clamp(cosine))
    const sine = Math.sin(theta)
    left = Math.sin((1-alpha)*theta) / sine
    right = Math.sin(alpha*theta) / sine
  }
  return normalizeOrientation({
    x: from.x*left + to.x*right,
    y: from.y*left + to.y*right,
    z: from.z*left + to.z*right,
    w: from.w*left + to.w*right,
  })
}

export const rotateVector = (q, v) => {
  const tx = 2 * (q.y*v.z - q.z*v.y)
  const ty = 2 * (q.z*v.x - q.x*v.z)
  const tz = 2 * (q.x*v.y - q.y*v.x)
  return {
    x: v.x + q.w*tx + q.y*tz - q.z*ty,
    y: v.y + q.w*ty + q.z*tx - q.x*tz,
    z: v.z + q.w*tz + q.x*ty - q.y*tx,
  }
}

export function orientationTelemetry(orientation, fallback = {yaw: 0, pitch: 0, roll: 0}) {
  if (!orientation) return {...fallback}
  const q = normalizeOrientation(orientation)
  const nose = rotateVector(q, {x: 0, y: 0, z: -1})
  const up = rotateVector(q, {x: 0, y: 1, z: 0})
  const yaw = Math.atan2(nose.x, -nose.z)
  const pitch = Math.asin(clamp(nose.y))
  const right = {x: Math.cos(yaw), y: 0, z: Math.sin(yaw)}
  const levelUp = {
    x: -Math.sin(yaw)*Math.sin(pitch),
    y: Math.cos(pitch),
    z: Math.cos(yaw)*Math.sin(pitch),
  }
  const dot3 = (a, b) => a.x*b.x+a.y*b.y+a.z*b.z
  const roll = Math.atan2(-dot3(up,right), dot3(up,levelUp))
  return {yaw,pitch,roll}
}
