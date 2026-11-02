import assert from "node:assert/strict"
import test from "node:test"
import {FlightControls} from "./flight_controls.mjs"

const press = (code, extras = {}) => ({code, repeat: false, defaultPrevented: false,
  preventDefault(){this.prevented = true}, ...extras})

test("signed throttle passes through neutral into reverse, and clamps", () => {
  let time = 1000
  const events = []
  const flight = new FlightControls({send: value => events.push(value), now: () => time})
  for (let i = 0; i < 15; i++) {
    assert.equal(flight.keyDown(press("Minus")), true)
    time += 100
  }
  assert.equal(flight.throttle, -1)
  for (let i = 0; i < 10; i++) {
    flight.keyDown(press("NumpadAdd"))
    time += 100
  }
  assert.equal(flight.throttle, 0)
  flight.keyDown(press("Equal"))
  assert.equal(flight.throttle, 0.1)
  assert.equal(events.at(-1).throttle, 0.1)
})

test("W/X pitch, A/D yaw, Z/C roll and S center", () => {
  const events = []
  const flight = new FlightControls({send: value => events.push(value), now: () => 2000})
  flight.keyDown(press("KeyA"))
  flight.keyDown(press("KeyX"))
  flight.keyDown(press("KeyC"))
  assert.deepEqual(flight.axes(), {yaw: -1, pitch: 1, roll: 1})
  flight.keyUp(press("KeyA"))
  assert.equal(flight.axes().yaw, 0)
  flight.keyDown(press("KeyS"))
  assert.deepEqual(flight.axes(), {yaw: 0, pitch: 0, roll: 0})
  assert.equal(events.at(-1).roll, 0)
})

test("Ctrl+E changes flight mode and does not interfere with typing", () => {
  const events = []
  const flight = new FlightControls({send: value => events.push(value), now: () => 2000})
  assert.equal(flight.keyDown(press("KeyE")), false)
  assert.equal(flight.keyDown(press("KeyE", {ctrlKey:true})), true)
  assert.equal(flight.mode, "newtonian")
  assert.equal(flight.keyDown(press("KeyE", {ctrlKey:true, repeat:true})), true)
  assert.equal(flight.mode, "newtonian")
  assert.equal(flight.keyDown(press("KeyA",{target:{tagName:"INPUT"}})), false)
  assert.deepEqual(flight.axes(), {yaw:0, pitch:0, roll:0})
  assert.equal(events.length, 1)
})

test("axis hold heartbeats, releasing focus sends zero and autopilot reset is silent", () => {
  let time = 2000
  const events = []
  const flight = new FlightControls({send: value => events.push(value), now: () => time})
  flight.keyDown(press("KeyD"))
  flight.heartbeat(time + 50)
  assert.equal(events.length,1)
  time += 350
  flight.heartbeat(time)
  assert.equal(events.length,2)
  flight.release()
  assert.equal(events.at(-1).yaw,0)
  const count = events.length
  flight.resetThrottle()
  assert.equal(events.length,count)
})
