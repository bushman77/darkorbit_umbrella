// A sensor-derived visual flyby, NOT a local combat spawn or collision body.
// Coordinates originate in the shared SOL simulation. View-relative bearing
// uses the strategic cruise heading, independent of the legacy sector camera.
const validCoord = v => v && [v.x, v.y, v.z].every(Number.isFinite)

export function encounterRenderSpec(navigation) {
  const encounter = navigation?.encounter
  if (navigation?.status !== "traveling" ||
      !encounter || encounter.mode !== "strategic_flyby" ||
      typeof encounter.id !== "string" ||
      !validCoord(encounter.relative_position_km) ||
      !validCoord(navigation.origin_position_km) ||
      !validCoord(navigation.destination_position_km) ||
      !Number.isFinite(encounter.distance_km) ||
      encounter.distance_km < 0 || encounter.distance_km > 650_000) return null

  const from = navigation.origin_position_km
  const to = navigation.destination_position_km
  const dx = to.x - from.x, dy = to.y - from.y
  const length = Math.hypot(dx, dy)
  if (length < 1) return null

  // Local -Z follows the SOL route. +X is to its right. Contact direction
  // is projected at a fixed near-camera visual distance for both SBS eyes.
  const fx = dx / length, fy = dy / length
  const r = encounter.relative_position_km
  const forward = (r.x * fx + r.y * fy)
  const right = (r.x * fy - r.y * fx)
  const magnitude = Math.hypot(right, forward, r.z)
  if (magnitude < 1) return null

  const distance = 90
  return {
    id: encounter.id,
    callSign: typeof encounter.call_sign === "string" ? encounter.call_sign : "CONTACT",
    distanceKm: encounter.distance_km,
    position: {
      x: right / magnitude * distance,
      y: r.z / magnitude * distance,
      z: -forward / magnitude * distance,
    },
    scale: 2.2,
  }
}
