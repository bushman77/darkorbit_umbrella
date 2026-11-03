import test from "node:test"
import assert from "node:assert/strict"
import {
  MouseSteering, mouseSteeringAxes, MOUSE_STEERING_IDLE_MS,
  validMouseSensitivity,
} from "./mouse_steering.mjs"

test("mouse yaw/pitch control remains bounded and sensitivity remains 0.4x-6x", () => {
  assert.deepEqual(mouseSteeringAxes(5.5, -5.5), {yaw: 0.5, pitch: 0.5})
  assert.deepEqual(mouseSteeringAxes(-5.5, 5.5), {yaw: -0.5, pitch: -0.5})
  assert.deepEqual(mouseSteeringAxes(0, 0), {yaw: 0, pitch: 0})
  assert.deepEqual(mouseSteeringAxes(2000, -2000), {yaw: 1, pitch: 1})
  assert.deepEqual(mouseSteeringAxes(-2000, 2000), {yaw: -1, pitch: -1})
  assert.equal(mouseSteeringAxes(5.5, 0, 2).yaw, 1)
  assert.equal(mouseSteeringAxes(5.5, 0, 0.4).yaw, 0.2)
  assert.equal(mouseSteeringAxes(2, 0, 6).yaw, 1)
  assert.equal(mouseSteeringAxes(5.5, 0, Infinity).yaw, 0.5)
  assert.equal(mouseSteeringAxes(5.5, 0, 100).yaw, 0.5)
  assert.equal(validMouseSensitivity(6.0), true)
  assert.equal(validMouseSensitivity(6.1), false)
  assert.equal(validMouseSensitivity(0.39), false)
})

test("rapid small movements still accumulate during continuous movement", () => {
  let time = 1000
  const mouse = new MouseSteering({now: () => time})
  assert.ok(mouse.move(1, 0).yaw > 0.08)
  time += 8
  const two = mouse.move(1, 0).yaw
  assert.ok(two > 0.12)
  time += 8
  const three = mouse.move(1, 0).yaw
  assert.ok(three > two)
  assert.ok(three <= 1)
})

test("stopping mouse motion snaps the command to neutral after 25ms, with no fade", () => {
  let time = 1000
  const mouse = new MouseSteering({now: () => time})
  assert.deepEqual(mouse.move(11, -5.5), {yaw: 1, pitch: 0.5})
  time += MOUSE_STEERING_IDLE_MS - 1
  assert.equal(mouse.expire(time), null)
  time += 1
  assert.deepEqual(mouse.expire(time), {yaw: 0, pitch: 0})
  time += 1000
  assert.equal(mouse.expire(time), null)
  assert.deepEqual(mouse.axes(), {yaw: 0, pitch: 0})
})

test("zero-delta browser events cannot extend turning beyond the short stop window", () => {
  let time = 1000
  const mouse = new MouseSteering({now: () => time})
  assert.deepEqual(mouse.move(11, -5.5), {yaw: 1, pitch: 0.5})
  time += MOUSE_STEERING_IDLE_MS - 1
  assert.deepEqual(mouse.move(0, 0), {yaw: 1, pitch: 0.5})
  assert.equal(mouse.expire(time), null)
  time += 1
  assert.deepEqual(mouse.expire(time), {yaw: 0, pitch: 0})
})

test("moving only one axis immediately clears carry from the other axis", () => {
  let time = 1000
  const mouse = new MouseSteering({now: () => time})
  mouse.move(11, -5.5)
  time += 8
  assert.deepEqual(mouse.move(0, -5.5), {yaw: 0, pitch: 0.75})
  time += 8
  assert.deepEqual(mouse.move(-5.5, 0), {yaw: -0.5, pitch: 0})
})

test("reversing direction immediately obeys new mouse movement", () => {
  let time = 1000
  const mouse = new MouseSteering({now: () => time})
  mouse.move(11, -11)
  time += 8
  assert.deepEqual(mouse.move(-5.5, 5.5), {yaw: -0.5, pitch: -0.5})
  time += MOUSE_STEERING_IDLE_MS
  assert.deepEqual(mouse.expire(time), {yaw: 0, pitch: 0})
  time += 1
  assert.deepEqual(mouse.move(-11, 11), {yaw: -1, pitch: -1})
})

test("release clears input immediately and retains chosen sensitivity", () => {
  let time = 1000
  const mouse = new MouseSteering({now: () => time, sensitivity: 1.5})
  mouse.move(5.5, 0)
  assert.equal(mouse.axes().yaw, 0.75)
  assert.deepEqual(mouse.release(), {yaw: 0, pitch: 0})
  assert.equal(mouse.sensitivity, 1.5)
})

test("same-direction carry never survives a mouse pause longer than the idle cutoff", () => {
  let time = 1000
  const mouse = new MouseSteering({now: () => time})
  mouse.move(5.5, 0)
  time += 8
  assert.equal(mouse.move(5.5, 0).yaw, 0.75)
  // A delayed event must represent fresh movement rather than dragging a
  // previous steering rate along for another 120ms.
  time += MOUSE_STEERING_IDLE_MS + 1
  assert.equal(mouse.move(5.5, 0).yaw, 0.5)
  time += MOUSE_STEERING_IDLE_MS
  assert.deepEqual(mouse.expire(), {yaw: 0, pitch: 0})
})

test("idle detection stays below two 60Hz frames, and no fade is emitted", () => {
  assert.ok(MOUSE_STEERING_IDLE_MS < 34)
  let time = 2000
  const mouse = new MouseSteering({now: () => time})
  mouse.move(10, 0)
  time += MOUSE_STEERING_IDLE_MS
  assert.deepEqual(mouse.expire(time), {yaw: 0, pitch: 0})
  time += 5
  assert.equal(mouse.expire(time), null)
})
