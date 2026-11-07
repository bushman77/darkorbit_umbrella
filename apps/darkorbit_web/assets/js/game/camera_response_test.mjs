import assert from "node:assert/strict"
import test from "node:test"
import {
  cameraSettleSeconds,
  STANDARD_CAMERA_SETTLE_SECONDS,
  POINTER_LOCK_CAMERA_SETTLE_SECONDS,
} from "./camera_response.mjs"
import {smoothOrientation} from "./orientation_interpolation.mjs"

test("pointer-locked local camera catches up faster, other pilots and keyboard unchanged", () => {
  assert.equal(STANDARD_CAMERA_SETTLE_SECONDS, 0.085)
  assert.equal(POINTER_LOCK_CAMERA_SETTLE_SECONDS, 0.025)
  assert.equal(cameraSettleSeconds({ownShip: true, pointerLocked: true}), 0.025)
  assert.equal(cameraSettleSeconds({ownShip: true, pointerLocked: false}), 0.085)
  assert.equal(cameraSettleSeconds({ownShip: false, pointerLocked: true}), 0.085)
  assert.equal(cameraSettleSeconds({ownShip: false, pointerLocked: false}), 0.085)
})

test("fast local interpolation reduces trailing without changing the server quaternion", () => {
  const start = {x: 0, y: 0, z: 0, w: 1}
  const target = {x: 0, y: -Math.sin(Math.PI / 12), z: 0, w: Math.cos(Math.PI / 12)}
  const fast = smoothOrientation(start, target, 1 / 60, POINTER_LOCK_CAMERA_SETTLE_SECONDS)
  const usual = smoothOrientation(start, target, 1 / 60, STANDARD_CAMERA_SETTLE_SECONDS)
  assert.ok(Math.abs(fast.y) > Math.abs(usual.y))
  assert.ok(Math.abs(fast.y) < Math.abs(target.y))
  assert.deepEqual(target, {x: 0, y: -Math.sin(Math.PI / 12), z: 0, w: Math.cos(Math.PI / 12)})
})
