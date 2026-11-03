import assert from "node:assert/strict"
import test from "node:test"
import {
  planetaryRenderSpec, generatePlanetPixels, PLANET_APPEARANCE, planetAppearance,
} from "./planetary_view.mjs"

const sample = (body_id = "venus", angular_diameter_deg = 65, radius_km = 6051.8) => ({
  body_id,
  radius_km,
  visual_distance_km: radius_km / Math.sin(angular_diameter_deg * Math.PI / 360),
  angular_diameter_deg,
  stage: "orbital_preview",
  visual_only: true,
})

test("Venus near orbital staging fills almost the entire 70-degree vertical cockpit", () => {
  const result = planetaryRenderSpec(sample())
  assert.equal(result.id, "venus")
  assert.equal(result.stage, "orbital_preview")
  assert.ok(result.angularDiameterDeg > 64.99)
  assert.ok(result.angularDiameterDeg < 65.01)
  assert.ok(result.sceneRadius > 480)
  assert.ok(result.sceneRadius < 490)
  assert.ok(result.sceneDistance - result.sceneRadius > 0)
  assert.ok(result.sceneDistance + result.sceneRadius < 3000)
})

test("planets grow predictably without changing the cockpit clipping plane", () => {
  const distant = planetaryRenderSpec(sample("venus", 1.5))
  const midway = planetaryRenderSpec(sample("venus", 23))
  const arrived = planetaryRenderSpec(sample("venus", 65))
  assert.ok(distant.sceneRadius < midway.sceneRadius)
  assert.ok(midway.sceneRadius < arrived.sceneRadius)
  assert.equal(distant.sceneDistance, 900)
  assert.equal(midway.sceneDistance, 900)
  assert.equal(arrived.sceneDistance, 900)
})

test("server visual metadata must be bounded and internally consistent", () => {
  assert.equal(planetaryRenderSpec(null), null)
  assert.equal(planetaryRenderSpec({...sample(), body_id: "../invented"}), null)
  assert.equal(planetaryRenderSpec({...sample(), visual_only: false}), null)
  assert.equal(planetaryRenderSpec({...sample(), radius_km: -1}), null)
  assert.equal(planetaryRenderSpec({...sample(), visual_distance_km: 0}), null)
  assert.equal(planetaryRenderSpec({...sample(), angular_diameter_deg: 12}), null)
  assert.equal(planetaryRenderSpec({...sample(), stage: "combat_authority"}), null)
  assert.equal(planetaryRenderSpec(sample(), -100), null)
})

test("Venus cloud texture is procedural, deterministic and fully opaque", () => {
  assert.ok(PLANET_APPEARANCE.venus)
  const a = generatePlanetPixels("venus", 48, 24)
  const b = generatePlanetPixels("venus", 48, 24)
  assert.deepEqual(a.pixels, b.pixels)
  assert.equal(a.pixels.length, 48 * 24 * 4)
  const colors = new Set()
  for (let i = 0; i < a.pixels.length; i += 4) {
    assert.equal(a.pixels[i + 3], 255)
    colors.add(`${a.pixels[i]}:${a.pixels[i + 1]}:${a.pixels[i + 2]}`)
  }
  assert.ok(colors.size > 20)
  assert.equal(generatePlanetPixels("../invalid", 48, 24), null)
  assert.equal(generatePlanetPixels("venus", -1, 24), null)
  assert.equal(generatePlanetPixels("venus", 3000, 24), null)
})

test("Earth uses the same validated real-radius projection as Venus", () => {
  const earth = planetaryRenderSpec(sample("earth", 65, 6371.0))
  assert.equal(earth.id, "earth")
  assert.ok(earth.sceneRadius > 480)
  assert.ok(earth.sceneRadius < 490)
})

test("future registered bodies use a procedural default without code changes", () => {
  const newPlanet = planetaryRenderSpec(sample("proxima-b", 65, 7000))
  assert.equal(newPlanet.id, "proxima-b")
  assert.ok(planetAppearance("proxima-b"))
  const pixels = generatePlanetPixels("proxima-b", 32, 16)
  assert.equal(pixels.pixels.length, 32 * 16 * 4)
  assert.deepEqual(pixels.pixels, generatePlanetPixels("proxima-b", 32, 16).pixels)
  assert.equal(planetAppearance("../../html"), null)
  assert.equal(generatePlanetPixels("__proto__", 32, 16), null)
})
