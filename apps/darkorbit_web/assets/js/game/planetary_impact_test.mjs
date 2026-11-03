import assert from "node:assert/strict"
import test from "node:test"
import {planetaryImpactMessage} from "./planetary_impact.mjs"

test("a server-confirmed Venus crash receives a clear fatal-impact message", () => {
  assert.equal(planetaryImpactMessage({
    reason: "planetary_collision", planet_id: "venus"
  }), "PLANETARY IMPACT · VENUS · SHIP DESTROYED")
})

test("normal ship deaths and proximity alone never manufacture a collision", () => {
  assert.equal(planetaryImpactMessage({reason: "player_destroyed", planet_id: "venus"}), null)
  assert.equal(planetaryImpactMessage({planet_id: "venus"}), null)
  assert.equal(planetaryImpactMessage(null), null)
  assert.equal(planetaryImpactMessage({reason: "planetary_collision", planet_id: "<img>"}),
    "PLANETARY IMPACT · PLANET · SHIP DESTROYED")
})
