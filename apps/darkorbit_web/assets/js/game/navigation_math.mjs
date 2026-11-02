import {minimapProjection} from "./minimap_renderer.mjs"

export const NAV_CHART_SIZE = Object.freeze({width: 1000, height: 600})
export const MAX_WAYPOINTS = 8

export const chartProjection = boundaries => minimapProjection(boundaries, NAV_CHART_SIZE, 34)

export const chartWorldPoint = (point, boundaries) => {
  if (!Number.isFinite(point?.x) || !Number.isFinite(point?.y)) return null
  return chartProjection(boundaries)?.worldPoint(point) || null
}

export function validWaypoint(point, boundaries) {
  if (!point || !boundaries || !Number.isFinite(point.x) || !Number.isFinite(point.y)) return null
  if (!(boundaries.width > 0) || !(boundaries.height > 0)) return null
  if (point.x < 0 || point.y < 0 || point.x > boundaries.width || point.y > boundaries.height) return null
  return {x: point.x, y: point.y}
}

export function appendWaypoint(draft, point, boundaries) {
  if (!Array.isArray(draft) || draft.length >= MAX_WAYPOINTS) return draft
  const normalized = validWaypoint(point, boundaries)
  if (!normalized) return draft
  const previous = draft.at(-1)
  if (previous && Math.hypot(previous.x - normalized.x, previous.y - normalized.y) < 1) return draft
  return [...draft, normalized]
}

export function routeDistance(origin, waypoints) {
  if (!origin || !Array.isArray(waypoints)) return 0
  let total = 0
  let last = origin
  for (const point of waypoints) {
    if (!Number.isFinite(last?.x) || !Number.isFinite(last?.y) ||
        !Number.isFinite(point?.x) || !Number.isFinite(point?.y)) return 0
    total += Math.hypot(point.x - last.x, point.y - last.y)
    last = point
  }
  return total
}

export function parseCoordinates(rawX, rawY, boundaries) {
  if (String(rawX).trim() === "" || String(rawY).trim() === "") return null
  return validWaypoint({x: Number(rawX), y: Number(rawY)}, boundaries)
}
