import test from "node:test"
import assert from "node:assert/strict"
import {
  MouseSteering, mouseSteeringAxes, MOUSE_STEERING_IDLE_MS,
  MOUSE_STEERING_DECAY_MS, validMouseSensitivity,
} from "./mouse_steering.mjs"

test("mouse yaw/pitch control remains bounded and consistent", () => {
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

test("short movement packet bursts accumulate rather than replacing last 1px event", () => {
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

test("zero movement packets neither stop steering nor keep resetting expiry", () => {
  let time = 1000
  const mouse = new MouseSteering({now: () => time})
  mouse.move(11, -5.5)
  time += MOUSE_STEERING_IDLE_MS - 10
  assert.deepEqual(mouse.move(0, 0), {yaw: 1, pitch: 0.5})
  assert.equal(mouse.expire(time), null)
  time += 10 + MOUSE_STEERING_DECAY_MS
  const decay = mouse.expire(time)
  assert.ok(decay.yaw > 0 && decay.yaw < 1)
  assert.ok(decay.pitch > 0 && decay.pitch < 0.5)
})

test("after idle grace period the ship smoothly returns to neutral", () => {
  let time = 1000
  const mouse = new MouseSteering({now: () => time})
  assert.deepEqual(mouse.move(11, -5.5), {yaw: 1, pitch: 0.5})
  time += MOUSE_STEERING_IDLE_MS - 1
  assert.equal(mouse.expire(time), null)
  time += 1
  assert.deepEqual(mouse.expire(time), {yaw: 1, pitch: 0.5})
  time += MOUSE_STEERING_DECAY_MS
  const relaxed = mouse.expire(time)
  assert.ok(relaxed.yaw < 0.5 && relaxed.yaw > 0)
  assert.ok(relaxed.pitch < 0.25 && relaxed.pitch > 0)
  time += 2000
  assert.deepEqual(mouse.expire(time), {yaw: 0, pitch: 0})
  assert.equal(mouse.expire(time), null)
})

test("new motion after idle immediately restarts steering and resets decay", () => {
  let time = 1000
  const mouse = new MouseSteering({now: () => time})
  mouse.move(11, -5.5)
  time += 750
  mouse.expire(time)
  time += 100
  assert.deepEqual(mouse.move(-11, 5.5), {yaw: -1, pitch: -0.5})
  assert.equal(mouse.expire(time), null)
})

test("release clears input immediately and retains chosen sensitivity", () => {
  let time = 1000
  const mouse = new MouseSteering({now: () => time, sensitivity: 1.5})
  mouse.move(5.5, 0)
  assert.equal(mouse.axes().yaw, 0.75)
  assert.deepEqual(mouse.release(), {yaw: 0, pitch: 0})
  assert.equal(mouse.sensitivity, 1.5)
})
