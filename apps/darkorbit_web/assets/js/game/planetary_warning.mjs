// Server-authoritative proximity telemetry. The browser presents levels
// received from the current orbital map; it does not infer collisions or
// fabricate a safety radius from rendered planetary geometry.
export function planetaryWarningView(warning) {
  if (!warning || !["caution", "critical"].includes(warning.level) ||
      !Number.isFinite(warning.clearance_km) || warning.clearance_km < 0 ||
      typeof warning.planet_id !== "string") return null

  const planet = /^[a-z]+$/.test(warning.planet_id)
    ? warning.planet_id.toUpperCase()
    : "PLANET"

  const critical = warning.level === "critical"
  return {
    level: warning.level,
    label: critical ? "CRITICAL · PULL AWAY" : "CAUTION · PLANETARY PROXIMITY",
    detail: planet + " · " +
      Math.round(warning.clearance_km).toLocaleString("en-US") + " KM TO IMPACT",
    announcement: critical
      ? "Critical: collision with " + planet + " imminent. Pull away."
      : "Caution: approaching " + planet + "'s collision boundary.",
  }
}

// Snapshot payloads are authoritative and allow recovery after a missed event
// or joining while already inside an alert band.
export function ownPlanetaryWarning(snapshot, pilotId) {
  const warnings = snapshot?.planetary_warnings
  if (!Array.isArray(warnings) || pilotId == null) return null
  return warnings.find(warning =>
    warning && String(warning.entity_id) === String(pilotId)
  ) || null
}

export function proximityEventWarning(event, pilotId) {
  if (!event || pilotId == null ||
      String(event.entity_id) !== String(pilotId)) return undefined
  if (event.level === "clear") return null
  if (event.level !== "caution" && event.level !== "critical") return undefined
  return event
}
