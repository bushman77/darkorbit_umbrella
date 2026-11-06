import test from "node:test"
import assert from "node:assert/strict"
import {spaceBasePose, spaceBaseProjection} from "./space_base_view.mjs"

const earth = {
  id: "sol:base:earth", refinery_id: "sol:refinery:earth",
  body_id: "earth", model: "orbital_refinery_v1",
  position_3d: {x: 10000, y: 20000, z: 1000}, berth_count: 3,
}

test("server-published orbital station is placed in real local tactical coordinates", () => {
  const pose = spaceBasePose(earth)
  assert.deepEqual(pose.position, {x: 600, y: 60, z: 1200})
  assert.equal(pose.id, "sol:base:earth")
  assert.equal(pose.berthCount, 3)
})

test("rejects client-invented identities, models or malformed geometry", () => {
  for (const bad of [
    null, {}, {...earth, id: "sol:base:mars"},
    {...earth, model: "arbitrary"},
    {...earth, berth_count: 50},
    {...earth, position_3d: {x: NaN, y: 5, z: 7}},
  ]) assert.equal(spaceBasePose(bad), null)
})

test("station bearing is maintained and far geometry stays within camera clipping", () => {
  const pose = spaceBasePose(earth)
  const camera = {x: 0, y: 0, z: 0}
  const near = spaceBaseProjection(pose, camera)
  assert.deepEqual(near.position, pose.position)
  assert.equal(near.scale, 1)
  const distant = spaceBaseProjection(
    {position: {x: 5000, y: 5000, z: -5000}}, camera)
  assert.ok(distant.scale < 1)
  assert.ok(Math.hypot(...Object.values(distant.position)) <= 1600.00001)
  assert.ok(distant.position.x > 0 && distant.position.z < 0)
})

test("headset camera movement changes station position, never authoritative coordinates", () => {
  const pose = spaceBasePose(earth)
  const saved = {...pose.position}
  const moved = spaceBaseProjection(pose, {x: 100, y: 0, z: 0})
  assert.notDeepEqual(moved.position, pose.position)
  assert.deepEqual(pose.position, saved)
})
