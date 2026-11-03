import test from "node:test"
import assert from "node:assert/strict"
import {
  MouseSteering, mouseSteeringAxes, MOUSE_STEERING_IDLE_MS,
} from "./mouse_steering.mjs"

test("mouse movement supplies ship yaw and pitch, not roll or throttle", () => {
  const rightUp = mouseSteeringAxes(11, -11)
  assert.equal(rightUp.yaw, 0.5)
  assert.equal(rightUp.pitch, 0.5)
  assert.equal(Object.keys(rightUp).length, 2)
  const leftDown = mouseSteeringAxes(-11, 11)
  assert.equal(leftDown.yaw, -0.5)
  assert.equal(leftDown.pitch, -0.5)
  assert.deepEqual(mouseSteeringAxes(0, 0), {yaw: 0, pitch: 0})
})

test("large movement clamps and sensitivity is bounded", () => {
  assert.deepEqual(mouseSteeringAxes(2000, -2000), {yaw: 1, pitch: 1})
  assert.deepEqual(mouseSteeringAxes(-2000, 2000), {yaw: -1, pitch: -1})
  assert.equal(mouseSteeringAxes(11, 0, 2).yaw, 1)
  assert.equal(mouseSteeringAxes(11, 0, 0.4).yaw, 0.2)
  assert.equal(mouseSteeringAxes(11, 0, Infinity).yaw, 0.5)
  assert.equal(mouseSteeringAxes(11, 0, 100).yaw, 0.5)
})

test("mouse commands expire to zero shortly after movement stops", () => {
  let time = 1000
  const mouse = new MouseSteering({now: () => time})
  assert.deepEqual(mouse.move(22, -11), {yaw: 1, pitch: 0.5})
  time += MOUSE_STEERING_IDLE_MS - 1
  assert.equal(mouse.expire(time), null)
  time += 1
  assert.deepEqual(mouse.expire(time), {yaw: 0, pitch: 0})
  assert.equal(mouse.expire(time), null)
})

test("release clears input immediately and doesn't modify sensitivity", () => {
  let time = 1000
  const mouse = new MouseSteering({now: () => time, sensitivity: 1.5})
  mouse.move(11, 0)
  assert.equal(mouse.axes().yaw, 0.75)
  assert.deepEqual(mouse.release(), {yaw: 0, pitch: 0})
  assert.equal(mouse.sensitivity, 1.5)
})
