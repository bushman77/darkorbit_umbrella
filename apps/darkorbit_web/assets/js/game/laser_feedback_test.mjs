import assert from "node:assert/strict"
import test from "node:test"
import {laserFeedback, targetRange, LASER_FEEDBACK_MS} from "./laser_feedback.mjs"

test("the server confirms each wing hit and actual shield/hull changes", () => {
  const entities = new Map([["hostile", {displayName: "Rift Skirmisher"}]])
  const status = laserFeedback({
    hit: true, target_id: "hostile",
    beams: [{hit: true}, {hit: true}],
    shield_damage: 24, hull_damage: 16,
  }, entities, 1234)

  assert.deepEqual({
    hit: status.hit, beamHits: status.beamHits, beamCount: status.beamCount,
    shield: status.shield, hull: status.hull,
  }, {hit: true, beamHits: 2, beamCount: 2, shield: 24, hull: 16})
  assert.match(status.label, /HIT 2\/2/)
  assert.equal(status.detail, "RIFT SKIRMISHER")
  assert.equal(status.at, 1234)
})

test("miss is explicit and never invents an enemy or damage", () => {
  const status = laserFeedback({
    hit: false, beams: [{hit: false}, {hit: false}],
    shield_damage: 0, hull_damage: 0,
  }, new Map(), 200)
  assert.equal(status.hit, false)
  assert.equal(status.label, "MISS  /  NO IMPACT")
  assert.equal(status.beamHits, 0)
  assert.ok(LASER_FEEDBACK_MS >= 1200)
})

test("partial hits and legacy automatic shots report accurately", () => {
  const status = laserFeedback({
    hit: true, beams: [{hit: true}, {hit: false}],
    shield_damage: 10, hull_damage: 5,
  }, new Map(), 100)
  assert.match(status.label, /HIT 1\/2/)
  const old = laserFeedback({
    target: {id: "npc"}, shield_damage: 4, hull_damage: 2,
  }, new Map(), 100)
  assert.equal(old.hit, true)
  assert.equal(old.beamCount, 1)
})

test("full three-dimensional range is measured from ship to selected target", () => {
  const own = {target: {x: 1000, y: 1000, z: 0}, attackRange: 3600}
  const npc = {target: {x: 1000, y: 4200, z: 0}, shields: 375, hull: 784}
  assert.deepEqual(targetRange(own, npc), {
    distance: 3200, weaponRange: 3600, inRange: true,
    label: "RNG 3200/3600u  IN RANGE  SH 375  HULL 784",
  })
  npc.target.z = 2500
  const outside = targetRange(own,npc)
  assert.equal(outside.distance, 4061)
  assert.equal(outside.inRange,false)
  assert.match(outside.label,/OUT OF RANGE/)
  assert.equal(targetRange(null,npc),null)
})
