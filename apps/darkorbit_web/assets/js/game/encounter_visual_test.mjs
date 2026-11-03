import assert from "node:assert/strict"
import test from "node:test"
import {encounterRenderSpec} from "./encounter_visual.mjs"

const voyage = (relative = {x: 100000, y: 0, z: 0}, distance = 100000) => ({
  status: "traveling",
  origin_position_km: {x: 0, y: 0, z: 0},
  destination_position_km: {x: 1000000, y: 0, z: 0},
  encounter: {
    id: "flyby:traffic:sol:vesper-02:1",
    call_sign: "Vesper-02",
    mode: "strategic_flyby",
    distance_km: distance,
    relative_position_km: relative,
  },
})

test("a passing civilian ahead of the route appears ahead in both cockpit eyes", () => {
  const spec = encounterRenderSpec(voyage())
  assert.equal(spec.id, "flyby:traffic:sol:vesper-02:1")
  assert.equal(spec.callSign, "Vesper-02")
  assert.equal(spec.position.x, 0)
  assert.equal(spec.position.y, 0)
  assert.equal(spec.position.z, -90)
  assert.ok(spec.scale > 1.5)
  assert.ok(spec.scale < 4.7)
})

test("SOL route-relative bearing distinguishes behind, left, and up", () => {
  assert.equal(encounterRenderSpec(voyage({x: -900, y: 0, z: 0}, 900)).position.z, 90)
  // With eastbound cruise, -SOL-Y is the camera's right-hand side.
  assert.ok(encounterRenderSpec(voyage({x: 0, y: -900, z: 0}, 900)).position.x > 0)
  assert.ok(encounterRenderSpec(voyage({x: 0, y: 900, z: 0}, 900)).position.x < 0)
  assert.ok(encounterRenderSpec(voyage({x: 0, y: 0, z: 900}, 900)).position.y > 0)
})

test("visual size grows on approach, but only within server-provided encounter", () => {
  const far = encounterRenderSpec(voyage({x: 600000, y: 0, z: 0}, 600000))
  const near = encounterRenderSpec(voyage({x: 1500, y: 0, z: 0}, 1500))
  assert.ok(near.scale > far.scale)
  assert.equal(far.position.z, near.position.z)
  assert.equal(encounterRenderSpec({...voyage(), status: "idle"}), null)
  assert.equal(encounterRenderSpec({...voyage(), encounter: null}), null)
  assert.equal(encounterRenderSpec(voyage({x: 700000, y: 0, z: 0}, 700000)), null)
  assert.equal(encounterRenderSpec(voyage({x: NaN, y: 0, z: 0}, 2000)), null)
  assert.equal(encounterRenderSpec(voyage({x: 0, y: 0, z: 0}, 0)), null)
})
