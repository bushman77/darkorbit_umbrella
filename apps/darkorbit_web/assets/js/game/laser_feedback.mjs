// Interpret only the server's confirmed laser_fired events. These helpers
// never decide a hit or damage, and they work in both 3D and stereo mode.
export const LASER_FEEDBACK_MS = 1600

export function laserFeedback(shot, entities, at) {
  const rays = Array.isArray(shot.beams) ? shot.beams : null
  const beamCount = rays?.length || 1
  const beamHits = rays ? rays.filter(ray => ray.hit).length : (shot.hit === false ? 0 : 1)
  const hit = shot.hit === true || (shot.hit !== false &&
    (beamHits > 0 || Boolean(shot.target)))
  const shield = Math.max(0, Math.round(Number(shot.shield_damage) || 0))
  const hull = Math.max(0, Math.round(Number(shot.hull_damage) || 0))
  const firstId = shot.hits?.[0]?.target_id ?? shot.target_id
  const target = firstId == null ? null : entities?.get(String(firstId))
  const name = (target?.displayName || "TARGET").toUpperCase()
  return {
    at, hit, beamHits, beamCount, shield, hull,
    label: hit
      ? `HIT ${beamHits}/${beamCount}  SH -${shield}  HULL -${hull}`
      : "MISS  /  NO IMPACT",
    detail: hit ? name : "Aim the sight at an enemy ship",
  }
}

export function targetRange(own, target) {
  if (!own || !target) return null
  const a = own.target || own.render
  const b = target.target || target.render
  if (!a || !b) return null

  const distance = Math.round(Math.hypot(
    b.x - a.x, b.y - a.y, (b.z ?? 0) - (a.z ?? 0),
  ))
  const weaponRange = Number(own.attackRange) || 0
  return {
    distance, weaponRange, inRange: distance <= weaponRange,
    label: `RNG ${distance}/${weaponRange}u  ${distance <= weaponRange
      ? "IN RANGE" : "OUT OF RANGE"}  SH ${Math.round(target.shields || 0)}  HULL ${Math.round(target.hull || 0)}`,
  }
}
