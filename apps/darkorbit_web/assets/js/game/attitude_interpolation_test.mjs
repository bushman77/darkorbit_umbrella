import assert from "node:assert/strict"
import test from "node:test"
import {smoothAttitude, wrapAngle, angularDelta} from "./attitude_interpolation.mjs"

const near = (actual, expected, tol = 1.0e-9) =>
  assert.ok(Math.abs(actual - expected) < tol, `${actual} should be near ${expected}`)

test("zero delta leaves attitude unchanged and small frames are smooth", () => {
  const target = {yaw: 0.7, pitch: 0.5, roll: -0.3}
  let state = {yaw: 0, pitch: 0, roll: 0}
  assert.deepEqual(smoothAttitude(state, target, 0), state)

  state = smoothAttitude(state, target, 1 / 60)
  assert.ok(state.pitch > 0 && state.pitch < target.pitch)
  assert.ok(state.yaw > 0 && state.yaw < target.yaw)
  assert.ok(state.roll < 0 && state.roll > target.roll)

  for (let i = 0; i < 40; i++) state = smoothAttitude(state, target, 1 / 60)
  near(state.pitch, target.pitch, 0.001)
  near(state.yaw, target.yaw, 0.001)
})

test("crossing +/-180 degrees uses the shorter rotation", () => {
  const toRad = degrees => degrees * Math.PI / 180
  const initial = {yaw: toRad(179), pitch: 0, roll: -toRad(179)}
  const target = {yaw: -toRad(179), pitch: 0, roll: toRad(179)}
  const first = smoothAttitude(initial, target, 1 / 60)
  const yawTravel = angularDelta(initial.yaw, first.yaw)
  const rollTravel = angularDelta(initial.roll, first.roll)
  assert.ok(yawTravel > 0 && yawTravel < toRad(2))
  assert.ok(rollTravel < 0 && rollTravel > -toRad(2))
})

test("long browser frame is clamped; no overshoot or invalid number", () => {
  const target = {yaw: 0, pitch: -1, roll: 0}
  const current = {yaw: 0, pitch: 1, roll: 0}
  const result = smoothAttitude(current, target, 10)
  assert.ok(result.pitch < current.pitch && result.pitch > target.pitch)
  near(wrapAngle(Math.PI * 3), Math.PI)
})
