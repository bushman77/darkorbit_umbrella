import test from "node:test"
import assert from "node:assert/strict"
import {helmetPlanetaryNavigation} from "./helmet_planetary_navigation.mjs"

function planet(id, stage = "orbital_preview") {
  const radius = 6371
  const angle = 65 * Math.PI / 360
  return {
    body_id: id,
    radius_km: radius,
    visual_distance_km: radius / Math.sin(angle),
    angular_diameter_deg: 65,
    visual_only: true,
    stage,
    planet_center: {x: 100000, y: 200000, z: 0},
  }
}

test("HMD uses the verified planet from the pilot's navigation feed", () => {
  const visual = planet("mars")
  const navigation = helmetPlanetaryNavigation({planetary_view: visual})
  assert.deepEqual(navigation, {planetary_view: visual})
  assert.equal(navigation.planetary_view.body_id, "mars")
})

test("HMD clears planets on deep-space transitions and rejects malformed data", () => {
  assert.deepEqual(helmetPlanetaryNavigation({planetary_view: null}),
    {planetary_view: null})
  assert.deepEqual(helmetPlanetaryNavigation({planetary_view: {...planet("venus"),
    visual_distance_km: 1}}), {planetary_view: null})
  assert.deepEqual(helmetPlanetaryNavigation({planetary_view: {
    ...planet("venus"), visual_only: false}}), {planetary_view: null})
  assert.deepEqual(helmetPlanetaryNavigation(null), {planetary_view: null})
})
