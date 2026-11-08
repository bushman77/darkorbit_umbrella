// Station safety data comes from authoritative orbital positions, not the
// projected refinery mesh. The client never estimates a collision boundary.
export function ownStationWarning(snapshot, pilotId) {
  const warnings = snapshot?.station_warnings
  if (!Array.isArray(warnings) || pilotId == null) return null
  return warnings.find(warning =>
    warning && String(warning.entity_id) === String(pilotId)
  ) || null
}

export function stationWarningView(warning) {
  if (!warning || typeof warning.station_id !== "string") return null
  if (warning.station_id === "sol:starbase:green") {
    if (!["caution", "critical", "approach"].includes(warning.level) ||
        !Number.isFinite(warning.distance_km) || warning.distance_km < 0) return null
    const approach = warning.level === "approach"
    const critical = warning.level === "critical"
    return {
      level: warning.level,
      label: approach ? "GREEN STARBASE · OPEN BAY APPROACH" :
        critical ? "CRITICAL · GREEN STARBASE HULL" :
          "CAUTION · GREEN STARBASE PROXIMITY",
      detail: Math.round(warning.distance_km).toLocaleString("en-US") +
        " KM FROM STARBASE CENTER · DOCKING UNAVAILABLE",
      announcement: approach ? "Green Starbase approach corridor ahead. Docking is not yet active." :
        critical ? "Critical: Green Starbase hull nearby. Brake or change course." :
          "Caution: Green Starbase proximity.",
    }
  }
  if (!["caution", "critical"].includes(warning.level) ||
      !Number.isFinite(warning.clearance_km) || warning.clearance_km < 0 ||
      !/^sol:base:[a-z0-9_-]+$/.test(warning.station_id)) return null

  const critical = warning.level === "critical"
  return {
    level: warning.level,
    label: critical ? "CRITICAL · REFINERY COLLISION RISK" : "CAUTION · REFINERY APPROACH",
    detail: Math.round(warning.clearance_km).toLocaleString("en-US") +
      " KM TO STATION HULL · NO DOCKING CLEARANCE",
    announcement: critical
      ? "Critical: refinery hull ahead. Brake or change course."
      : "Caution: approaching an orbital refinery.",
  }
}
