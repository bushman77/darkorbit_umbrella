import {planetaryRenderSpec} from "./planetary_view.mjs"

// Helmet receives only visual metadata. Never treat it as simulation state
// or accept a caller-provided planet on the viewer socket.
export function helmetPlanetaryNavigation(payload) {
  const view = payload?.planetary_view
  const navigation = {
    planetary_view: planetaryRenderSpec(view) ? view : null,
    tactical_active: payload?.tactical_active === true,
  }

  // Green Starbase has the same locally bundled geometry on both desktop
  // and Android. The authenticated server supplies its read-only location
  // only while the pilot is at the actual deep-space station waypoint.
  const available = payload?.status === "idle" &&
    payload?.location_id === null &&
    payload?.green_starbase_nearby === true
  const station = available && Array.isArray(payload.starbases)
    ? payload.starbases.find(base =>
      base?.id === "sol:starbase:green" &&
      base?.model === "green_pyramid_starbase_v1" &&
      base?.site_3d &&
      [base.site_3d.x, base.site_3d.y, base.site_3d.z].every(Number.isFinite))
    : null

  if (station) {
    navigation.status = "idle"
    navigation.location_id = null
    navigation.green_starbase_nearby = true
    navigation.starbases = [{
      id: station.id,
      model: station.model,
      site_3d: {
        x: station.site_3d.x,
        y: station.site_3d.y,
        z: station.site_3d.z,
      },
    }]
  }

  return navigation
}
