import test from "node:test"
import assert from "node:assert/strict"
import {helmetPlanetaryNavigation} from "./helmet_planetary_navigation.mjs"
import {starbaseVisible} from "./green_starbase_visual.js"
import {readFileSync} from "node:fs"

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

const greenStarbase = {
  id: "sol:starbase:green",
  model: "green_pyramid_starbase_v1",
  site_3d: {x: 12000, y: 15500, z: 0},
}

test("Green Starbase renders in both SBS eyes from a minimal authenticated feed", () => {
  const navigation = helmetPlanetaryNavigation({
    status: "idle", location_id: null, green_starbase_nearby: true,
    starbases: [greenStarbase],
    contacts: [{cargo: {secret: 44}}],
  })
  assert.equal(starbaseVisible(navigation, "sol:free_15"), true)
  assert.equal(starbaseVisible(navigation, "sol:earth"), false)
  assert.equal(navigation.starbases.length, 1)
  assert.deepEqual(navigation.starbases[0], greenStarbase)
  assert.equal(navigation.contacts, undefined)

  const helmet = readFileSync(new URL("./helmet_client.mjs", import.meta.url), "utf8")
  assert.match(helmet, /this\.mapId = typeof map\.map_id === "string" \? map\.map_id : null/)
  const renderer = readFileSync(new URL("./stereo_view.js", import.meta.url), "utf8")
  assert.match(renderer, /this\.greenStarbase\.update\(navigation, client\.mapId\)/)
})

test("HMD clears the base when departing or receiving untrusted metadata", () => {
  const near = {status: "idle", location_id: null, green_starbase_nearby: true,
    starbases: [greenStarbase]}
  for (const invalid of [
    {...near, green_starbase_nearby: false},
    {...near, status: "traveling"},
    {...near, location_id: "earth"},
    {...near, starbases: []},
    {...near, starbases: [{...greenStarbase, site_3d: {x: Infinity, y: 0, z: 0}}]},
    {...near, starbases: [{...greenStarbase, model: "spoof"}]},
  ]) {
    assert.equal(starbaseVisible(helmetPlanetaryNavigation(invalid), "sol:free_15"), false)
  }
})

test("HMD uses the verified planet from the pilot's navigation feed", () => {
  const visual = planet("mars")
  const navigation = helmetPlanetaryNavigation({planetary_view: visual, tactical_active: false})
  assert.deepEqual(navigation, {planetary_view: visual, tactical_active: false})
  assert.equal(navigation.planetary_view.body_id, "mars")
})

test("HMD clears planets on deep-space transitions and rejects malformed data", () => {
  assert.deepEqual(helmetPlanetaryNavigation({planetary_view: null, tactical_active: false}),
    {planetary_view: null, tactical_active: false})
  assert.deepEqual(helmetPlanetaryNavigation({planetary_view: {...planet("venus"),
    visual_distance_km: 1}}), {planetary_view: null, tactical_active: false})
  assert.deepEqual(helmetPlanetaryNavigation({planetary_view: {
    ...planet("venus"), visual_only: false}}), {planetary_view: null, tactical_active: false})
  assert.deepEqual(helmetPlanetaryNavigation(null), {planetary_view: null, tactical_active: false})
})


test("HMD retains only a boolean tactical hint, never encounter details", () => {
  const navigation = helmetPlanetaryNavigation({tactical_active: true,
    encounter: {secret: "not forwarded"}, cargo: ["test"]})
  assert.deepEqual(navigation, {planetary_view: null, tactical_active: true})
  assert.equal(helmetPlanetaryNavigation({tactical_active: "true"}).tactical_active, false)
})
