// Browser syntax checks only. The authenticated Elixir server alone
// determines which planetary region a pilot may join and where they spawn.
//
// Support future systems and planets without baking their names into the
// client build (e.g. futureSystem:body). This is NOT an authorization rule.
export const ORBITAL_MAP_PATTERN =
  /^[a-z][a-z0-9_-]{0,31}:[a-z][a-z0-9_-]{0,39}$/

export const validOrbitalMapId = id =>
  typeof id === "string" && (id === "1-1" || ORBITAL_MAP_PATTERN.test(id))

export const shouldEnterOrbitalRegion = (current, next, switching = false) =>
  !switching && next !== current && validOrbitalMapId(next)
