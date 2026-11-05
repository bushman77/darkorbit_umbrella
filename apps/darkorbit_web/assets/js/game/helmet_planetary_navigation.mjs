import {planetaryRenderSpec} from "./planetary_view.mjs"

// Helmet receives only visual metadata. Never treat it as simulation state
// or accept a caller-provided planet on the viewer socket.
export function helmetPlanetaryNavigation(payload) {
  const view = payload?.planetary_view
  return {planetary_view: planetaryRenderSpec(view) ? view : null}
}
