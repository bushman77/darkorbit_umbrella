// Client-side allowlist only. Map identity and spawn position are still
// authenticated and selected by the Phoenix server.
export const ORBITAL_MAP_IDS = Object.freeze([
  "1-1", "sol:mercury", "sol:venus", "sol:mars", "sol:jupiter",
  "sol:saturn", "sol:uranus", "sol:neptune", "sol:pluto",
])

export const validOrbitalMapId = id =>
  typeof id === "string" && ORBITAL_MAP_IDS.includes(id)

export const shouldEnterOrbitalRegion = (current, next, switching = false) =>
  !switching && next !== current && validOrbitalMapId(next)
