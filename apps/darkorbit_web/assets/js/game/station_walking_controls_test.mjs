import test from "node:test"
import assert from "node:assert/strict"
import {stationAxes, StationWalkingControls} from "./station_walking_controls.mjs"

test("WASD and arrow keys yield only movement intentions", () => {
  assert.deepEqual(stationAxes(new Set(["KeyW", "KeyD"])),
    {forward: 1, strafe: 1, turn: 0})
  assert.deepEqual(stationAxes(new Set(["KeyW", "KeyS"])),
    {forward: 0, strafe: 0, turn: 0})
})

test("capture docked keys, leave flight keys untouched, neutralize on blur", () => {
  let active = false
  const commands = []
  const controls = new StationWalkingControls({active: () => active,
    canvas: null, win: {},
    sendWalk: x => commands.push(x), sendLook: () => {}})
  const key = code => ({code, target: {},
    preventDefault() {this.prevented = true},
    stopImmediatePropagation() {this.stopped = true}})
  assert.equal(controls.key(key("KeyW"), true), false)
  active = true
  const pressed = key("KeyW")
  assert.equal(controls.key(pressed, true), true)
  assert.equal(pressed.prevented, true)
  assert.deepEqual(commands.at(-1), {forward: 1, strafe: 0, turn: 0})
  controls.release()
  assert.deepEqual(commands.at(-1), {forward: 0, strafe: 0, turn: 0})
})

test("mouse look sends bounded yaw increments, not coordinates", () => {
  const turns = []
  const controls = new StationWalkingControls({active: () => true,
    canvas: null, win: {}, sendWalk: () => {},
    sendLook: x => turns.push(x)})
  controls.pendingLook = 0.9
  controls.flushLook(100)
  assert.equal(turns[0].delta_yaw, 0.35)
  assert.ok(controls.pendingLook > 0.5)
  controls.flushLook(200)
  assert.equal(turns[1].delta_yaw, 0.35)
})
