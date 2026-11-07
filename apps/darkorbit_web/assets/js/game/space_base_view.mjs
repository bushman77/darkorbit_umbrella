import {toScene} from "./stereo_math.mjs"

// Authoritative station position comes only from the current map snapshot.
// All coordinates are planet-local tactical units, NOT compressed SOL km.
export function spaceBasePose(input) {
  if (!input || typeof input.body_id !== "string" ||
      input.id !== "sol:base:" + input.body_id ||
      input.refinery_id !== "sol:refinery:" + input.body_id ||
      input.model !== "orbital_refinery_v1") return null

  const pos = input.position_3d
  if (!pos || ![pos.x, pos.y, pos.z].every(Number.isFinite)) return null
  if (input.berth_count !== 3) return null

  return {id: input.id, bodyId: input.body_id,
    position: toScene(pos), berthCount: input.berth_count}
}

// A long-range visual proxy preserves actual bearing and angular size while
// remaining inside the 3000-unit Three.js far clipping plane. It never alters
// physics, navigation, docking range or server-owned collision coordinates.
export function spaceBaseProjection(pose, camera, maxDepth = 1600) {
  if (!pose?.position || !camera ||
      ![camera.x, camera.y, camera.z].every(Number.isFinite)) return null
  const p = pose.position
  const dx = p.x - camera.x, dy = p.y - camera.y, dz = p.z - camera.z
  const length = Math.hypot(dx, dy, dz)
  if (!Number.isFinite(length)) return null
  const scale = length > maxDepth ? maxDepth / length : 1
  return {position: {
    x: camera.x + dx * scale, y: camera.y + dy * scale,
    z: camera.z + dz * scale,
  }, scale}
}
