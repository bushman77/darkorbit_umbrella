import assert from "node:assert/strict"
import test from "node:test"
import {flightBasis, degrees} from "./flight_basis.mjs"

const near = (value, expected) => assert.ok(Math.abs(value - expected) < 1e-9,
  `expected ${value} to be close to ${expected}`)

test("neutral looks north with world up in Three.js", () => {
  const {forward, up} = flightBasis()
  near(forward.x, 0)
  near(forward.y, 0)
  near(forward.z, -1)
  near(up.x, 0)
  near(up.y, 1)
  near(up.z, 0)
})

test("yaw changes left/right viewing direction without tilting up", () => {
  const right = flightBasis({yaw: Math.PI / 2})
  const left = flightBasis({yaw: -Math.PI / 2})
  near(right.forward.x, 1)
  near(left.forward.x, -1)
  near(right.forward.y, 0)
  near(left.forward.y, 0)
  near(right.up.y, 1)
  near(left.up.y, 1)
})

test("pitch changes altitude, roll tilts camera up without changing nose", () => {
  const pitch = flightBasis({pitch: Math.PI / 4})
  const roll = flightBasis({roll: Math.PI / 4})
  near(pitch.forward.y, Math.SQRT1_2)
  near(roll.forward.y, 0)
  near(roll.forward.x, 0)
  near(roll.forward.z, -1)
  near(roll.up.x, -Math.SQRT1_2)
  near(roll.up.y, Math.SQRT1_2)
  assert.equal(degrees(Math.PI/2),90)
})

test("basis keeps world-up perpendicular to heading for compound motion", () => {
  const {forward, up} = flightBasis({yaw: 0.63, pitch: 0.31, roll: 0.24})
  near(forward.x * up.x + forward.y * up.y + forward.z * up.z, 0)
  near(Math.hypot(forward.x, forward.y, forward.z),1)
  near(Math.hypot(up.x,up.y,up.z),1)
})
