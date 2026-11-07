import {findSolarBody} from "./solar_system.mjs"

// A right-click on empty space targets its real SOL coordinate, never an
// unrelated planet that happened to be selected earlier.
export function solarMenuTarget(clickedId, _selectedId, waypoint = null) {
  if (findSolarBody(clickedId)) return clickedId
  return validSolarWaypoint(waypoint) ? waypoint : null
}

export function validSolarWaypoint(point) {
  if (!point || typeof point !== "object") return false
  const {x,y,z} = point
  return [x,y,z].every(Number.isFinite) &&
    Math.hypot(x,y) >= 1_000_000 &&
    Math.hypot(x,y) <= 200_000_000 &&
    Math.abs(z) <= 10_000_000
}

export function canNavigateSolar(target, navigation, connected, pending) {
  if (!connected || pending || navigation?.system_id !== "sol" ||
      navigation.status !== "idle") return false
  if (typeof target === "string") {
    return Boolean(findSolarBody(target) && target !== "sun" &&
      navigation.location_id !== target)
  }
  return validSolarWaypoint(target) && (
    !navigation.position_km ||
    Math.hypot(target.x-navigation.position_km.x,
      target.y-navigation.position_km.y,
      target.z-navigation.position_km.z) >= 1)
}
