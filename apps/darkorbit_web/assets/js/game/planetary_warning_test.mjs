import assert from "node:assert/strict"
import test from "node:test"
import {
  planetaryWarningView, ownPlanetaryWarning, proximityEventWarning,
} from "./planetary_warning.mjs"

const warning = (level, clearance_km, planet_id = "venus") => ({
  level, clearance_km, planet_id,
})

test("CAUTION and CRITICAL show actual server-provided impact clearance", () => {
  const caution = planetaryWarningView(warning("caution", 3_594.4))
  assert.equal(caution.level, "caution")
  assert.equal(caution.label, "CAUTION · PLANETARY PROXIMITY")
  assert.equal(caution.detail, "VENUS · 3,594 KM TO IMPACT")

  const critical = planetaryWarningView(warning("critical", 1_307.3))
  assert.equal(critical.level, "critical")
  assert.equal(critical.label, "CRITICAL · PULL AWAY")
  assert.equal(critical.detail, "VENUS · 1,307 KM TO IMPACT")
  assert.match(critical.announcement, /Pull away/)
})

test("untrusted or missing input never manufactures a warning", () => {
  for (const input of [
    null, {}, warning("clear", 500), warning("critical", -1),
    warning("caution", Infinity), warning("critical", NaN),
    {level: "warning", clearance_km: 10, planet_id: "venus"},
  ]) {
    assert.equal(planetaryWarningView(input), null)
  }
  assert.equal(planetaryWarningView(warning("caution", 9, "<bad>")).detail,
    "PLANET · 9 KM TO IMPACT")
})

test("snapshot warning lookup is scoped to the authenticated local pilot", () => {
  const snapshot = {planetary_warnings: [
    {entity_id: 7, ...warning("critical", 250)},
    {entity_id: 42, ...warning("caution", 900, "mars")},
  ]}
  assert.equal(ownPlanetaryWarning(snapshot, "42").planet_id, "mars")
  assert.equal(ownPlanetaryWarning(snapshot, 7).level, "critical")
  assert.equal(ownPlanetaryWarning(snapshot, 100), null)
  assert.equal(ownPlanetaryWarning(null, 42), null)
  assert.equal(ownPlanetaryWarning({planetary_warnings: {}}, 42), null)
})

test("zone transitions from other pilots are ignored and retreat clears warning", () => {
  assert.equal(proximityEventWarning({entity_id: 8, level: "critical"}, 9), undefined)
  assert.equal(proximityEventWarning({entity_id: 8, level: "caution"}, null), undefined)
  assert.equal(proximityEventWarning({entity_id: 8, level: "clear"}, 8), null)
  assert.equal(proximityEventWarning({
    entity_id: 8, ...warning("critical", 40),
  }, "8").level, "critical")
  assert.equal(proximityEventWarning({entity_id: 8, level: "invalid"}, 8), undefined)
})
