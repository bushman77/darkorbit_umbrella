import test from "node:test"
import assert from "node:assert/strict"
import {
  MouseSteering, mouseSteeringAxes, MOUSE_STEERING_IDLE_MS,
  validMouseSensitivity,
} from "./mouse_steering.mjs"

test("mouse yaw and pitch are twice as responsive at the original 1x setting", () => {
  const rightUp = mouseSteeringAxes(5.5, -5.5)
  assert.equal(rightUp.yaw, 0.5)
  assert.equal(rightUp.pitch, 0.5)
  assert.equal(Object.keys(rightUp).length, 2)
  const leftDown = mouseSteeringAxes(-5.5, 5.5)
  assert.equal(leftDown.yaw, -0.5)
  assert.equal(leftDown.pitch, -0.5)
  assert.deepEqual(mouseSteeringAxes(0, 0), {yaw: 0, pitch: 0})
})

test("range expands to 6x, saturates safely, and rejects invalid factors", () => {
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

test("mouse commands still expire to zero shortly after movement stops", () => {
  let time = 1000
  const mouse = new MouseSteering({now: () => time})
  assert.deepEqual(mouse.move(11, -5.5), {yaw: 1, pitch: 0.5})
  time += MOUSE_STEERING_IDLE_MS - 1
  assert.equal(mouse.expire(time), null)
  time += 1
  assert.deepEqual(mouse.expire(time), {yaw: 0, pitch: 0})
  assert.equal(mouse.expire(time), null)
})

test("release clears input immediately and retains the chosen sensitivity", () => {
  let time = 1000
  const mouse = new MouseSteering({now: () => time, sensitivity: 1.5})
  mouse.move(5.5, 0)
  assert.equal(mouse.axes().yaw, 0.75)
  assert.deepEqual(mouse.release(), {yaw: 0, pitch: 0})
  assert.equal(mouse.sensitivity, 1.5)
})
