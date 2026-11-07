// The cockpit only renders a server-confirmed collision. Clients must never
// infer lethal contact or modify shields/hull based on their own graphics.
export function planetaryImpactMessage(event) {
  if (event?.reason !== "planetary_collision") return null
  const body = typeof event.planet_id === "string" &&
    /^[a-z][a-z0-9_-]{0,39}$/.test(event.planet_id) ? event.planet_id.toUpperCase() : "PLANET"
  return `PLANETARY IMPACT · ${body} · SHIP DESTROYED`
}
