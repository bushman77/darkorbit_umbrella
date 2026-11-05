// Solar System Atlas V1. Mean heliocentric distance is in AU, not game-world
// units. Body angles below are curated SCHEMATIC placements for an easy-to-read
// chart, NOT current ephemerides. Do not use them for travel or collision.
//
// Distances and orbital periods are rounded astronomical reference values.
// Main sources: NASA Science / Planet Sizes and Locations; NASA Solar System
// Facts; planetary semi-major axes and sidereal periods from the Solar System
// data tables. Pluto is deliberately included as a dwarf planet.
export const SOLAR_SYSTEM_ID = "sol"

export const SOLAR_BODIES = Object.freeze([
  {id:"sun",name:"Sun",kind:"star",au:0,years:0,phase:0,color:"#ffc85c",size:15},
  {id:"mercury",name:"Mercury",kind:"planet",au:0.387,years:0.241,phase:20,color:"#b8b7ad",size:5},
  {id:"venus",name:"Venus",kind:"planet",au:0.723,years:0.615,phase:69,color:"#efc69a",size:7},
  {id:"earth",name:"Earth",kind:"planet",au:1,years:1,phase:138,color:"#5facff",size:8},
  {id:"mars",name:"Mars",kind:"planet",au:1.524,years:1.881,phase:218,color:"#d57456",size:6},
  {id:"jupiter",name:"Jupiter",kind:"planet",au:5.203,years:11.86,phase:282,color:"#d2a27a",size:12},
  {id:"saturn",name:"Saturn",kind:"planet",au:9.582,years:29.46,phase:340,color:"#e5cd94",size:10},
  {id:"uranus",name:"Uranus",kind:"planet",au:19.201,years:84.02,phase:17,color:"#8ddbdc",size:9},
  {id:"neptune",name:"Neptune",kind:"planet",au:30.047,years:164.8,phase:120,color:"#568eff",size:9},
  {id:"pluto",name:"Pluto",kind:"dwarf_planet",au:39.482,years:247.9,phase:226,color:"#bcaa9c",size:5},
].map(body => Object.freeze(body)))

export const SOLAR_FOCUSES = Object.freeze(["system", "inner"])
export const findSolarBody = id => SOLAR_BODIES.find(body => body.id === id) || null
export const bodiesForFocus = (focus = "system") => SOLAR_BODIES.filter(
  body => focus !== "inner" || body.au <= 1.524
)

// Nonlinear radial mapping. The full display keeps Mercury and Pluto visible,
// while the inner focus magnifies orbits through Mars. Physical sizes are
// diagrammatic as well, not a claim of accurate scale.
export function orbitRadius(au, focus = "system") {
  if (!Number.isFinite(au) || au < 0) return null
  if (au === 0) return 0
  if (focus === "inner") return 16 + 262 * Math.sqrt(au / 1.524)
  return 17 + 262 * Math.log1p(au) / Math.log1p(39.482)
}

export function solarLayout(focus = "system") {
  return bodiesForFocus(focus).map(body => {
    const radius = orbitRadius(body.au, focus)
    const angle = body.phase * Math.PI / 180
    return Object.freeze({
      ...body,orbitRadius:radius,
      x: 500 + radius * Math.cos(angle),
      y: 300 + radius * Math.sin(angle),
    })
  })
}

export const solarClass = kind =>
  kind === "dwarf_planet" ? "Dwarf planet" : kind === "planet" ? "Planet" : "Star"

export function solarBodySummary(body) {
  if (!body) return null
  if (body.kind === "star") return {
    heading:body.name,classification:"G-type main-sequence star",
    distance:"System center",period:"—",
  }
  return {
    heading:body.name,classification:solarClass(body.kind),
    distance:body.au.toFixed(3).replace(/0+$/,"").replace(/\.$/,"")+" AU",
    period:body.years < 1
      ? Math.round(body.years * 365.25)+" days"
      : body.years.toFixed(body.years < 10 ? 2 : 1)+" Earth years",
  }
}

 
// The Atlas uses a reversible display projection. World coordinates are the
// server's compressed SOL game-kilometres, never the local cockpit map units.
// Keep these coefficients synchronized with Core.Universe.Sol and test markers.
const GAME_KM_PER_LOG_AU = 16_000_000
const OUTER_GAME_KM_PER_AU = 800_000
const OUTER_THRESHOLD_AU = 10
const OUTSIDE_ORBIT_KM_PER_PIXEL = 250_000

export function solarGameRadius(au) {
  if (!Number.isFinite(au) || au < 0) return null
  return GAME_KM_PER_LOG_AU * Math.log1p(au) +
    OUTER_GAME_KM_PER_AU * Math.max(0, au - OUTER_THRESHOLD_AU)
}

function gameRadiusToAU(radius) {
  if (radius <= solarGameRadius(OUTER_THRESHOLD_AU)) {
    return Math.expm1(radius / GAME_KM_PER_LOG_AU)
  }
  let low = OUTER_THRESHOLD_AU, high = 5000
  for (let i = 0; i < 55; i++) {
    const mid = (low + high) / 2
    if (solarGameRadius(mid) < radius) low = mid
    else high = mid
  }
  return (low + high) / 2
}

export function solarPositionToChart(position, focus = "system") {
  if (!position || ![position.x,position.y,position.z].every(Number.isFinite)) return null
  const distance = Math.hypot(position.x, position.y)
  const edgeAU = focus === "inner" ? 1.524 : 39.482
  const edgeKM = solarGameRadius(edgeAU)
  const edgePX = orbitRadius(edgeAU, focus)
  const pixels = distance > edgeKM
    ? edgePX + (distance - edgeKM) / OUTSIDE_ORBIT_KM_PER_PIXEL
    : orbitRadius(gameRadiusToAU(distance), focus)
  const angle = Math.atan2(position.y, position.x)
  return {x: 500 + pixels * Math.cos(angle), y: 300 + pixels * Math.sin(angle)}
}

export function solarChartToPosition(x, y, focus = "system", z = 0) {
  if (![x,y,z].every(Number.isFinite) || !SOLAR_FOCUSES.includes(focus)) return null
  const radius = Math.hypot(x - 500, y - 300)
  const edgeAU = focus === "inner" ? 1.524 : 39.482
  const edgePX = orbitRadius(edgeAU, focus)
  const edgeKM = solarGameRadius(edgeAU)
  const au = focus === "inner"
    ? 1.524 * Math.pow(Math.max(0,radius - 16) / 262, 2)
    : Math.expm1(Math.max(0,radius - 17) / 262 * Math.log1p(39.482))
  const distance = radius > edgePX
    ? edgeKM + (radius - edgePX) * OUTSIDE_ORBIT_KM_PER_PIXEL
    : solarGameRadius(au)
  const angle = Math.atan2(y - 300, x - 500)
  return {x: distance * Math.cos(angle), y: distance * Math.sin(angle), z}
}
