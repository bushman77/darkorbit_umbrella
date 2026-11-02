// Server game coordinates: x east, y south, z up.
// Three.js rendering: x east, y up, z south. Zero attitude looks north (-Z).
// Independent forward and up vectors keep yaw, pitch, and roll distinguishable.
export function flightBasis({yaw = 0, pitch = 0, roll = 0} = {}) {
  const horizontal = Math.cos(pitch)
  const forward = {
    x: Math.sin(yaw) * horizontal,
    y: Math.sin(pitch),
    z: -Math.cos(yaw) * horizontal,
  }
  const right = {x: Math.cos(yaw), y: 0, z: Math.sin(yaw)}
  const levelUp = {
    x: -Math.sin(yaw) * Math.sin(pitch),
    y: Math.cos(pitch),
    z: Math.cos(yaw) * Math.sin(pitch),
  }
  const c = Math.cos(roll)
  const s = Math.sin(roll)
  const up = {
    x: levelUp.x * c - right.x * s,
    y: levelUp.y * c - right.y * s,
    z: levelUp.z * c - right.z * s,
  }
  return {forward, up}
}

export function degrees(radians) {
  return Math.round((Number.isFinite(radians) ? radians : 0) * 180 / Math.PI)
}
