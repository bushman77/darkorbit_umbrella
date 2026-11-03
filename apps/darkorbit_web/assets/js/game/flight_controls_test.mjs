import assert from "node:assert/strict"
import test from "node:test"
import {FlightControls} from "./flight_controls.mjs"

const press = (code, extras = {}) => ({
  code, repeat: false, defaultPrevented: false,
  preventDefault() { this.prevented = true },
  ...extras,
})

test("W/S pitch up/down, A/D yaw left/right, Q/E roll left/right independently", () => {
  const events = []
  const flight = new FlightControls({send: payload => events.push(payload), now: () => 1000})

  const cases = [
    ["KeyW", {pitch: 1, yaw: 0, roll: 0}],
    ["KeyS", {pitch: -1, yaw: 0, roll: 0}],
    ["KeyA", {pitch: 0, yaw: -1, roll: 0}],
    ["KeyD", {pitch: 0, yaw: 1, roll: 0}],
    ["KeyQ", {pitch: 0, yaw: 0, roll: -1}],
    ["KeyE", {pitch: 0, yaw: 0, roll: 1}],
  ]
  for (const [code, expected] of cases) {
    const event = press(code)
    assert.equal(flight.keyDown(event), true)
    assert.equal(event.prevented, true)
    assert.deepEqual(flight.axes(), {yaw: expected.yaw, pitch: expected.pitch, roll: expected.roll})
    assert.equal(flight.throttle, 0)
    assert.equal(events.at(-1).throttle, 0)
    assert.equal(flight.keyUp(press(code)), true)
    assert.deepEqual(flight.axes(), {yaw: 0, pitch: 0, roll: 0})
  }
})

test("pressing S immediately reverses pitch even when W remains registered", () => {
  const events = []
  const flight = new FlightControls({send: p => events.push(p), now: () => 1000})
  flight.keyDown(press("KeyW"))
  assert.equal(flight.axes().pitch, 1)
  flight.keyDown(press("KeyS"))
  assert.equal(flight.axes().pitch, -1)
  assert.equal(events.at(-1).pitch, -1)
  // Releasing the last key returns control to the remaining held key.
  flight.keyUp(press("KeyS"))
  assert.equal(flight.axes().pitch, 1)
  flight.keyUp(press("KeyW"))
  assert.equal(flight.axes().pitch, 0)
  assert.equal(flight.lastPitchKey, null)
})

test("S down can also be overridden by a fresh W up press", () => {
  const flight = new FlightControls({send: () => {}, now: () => 1000})
  flight.keyDown(press("KeyS"))
  flight.keyDown(press("KeyW"))
  assert.equal(flight.axes().pitch, 1)
  flight.keyUp(press("KeyW"))
  assert.equal(flight.axes().pitch, -1)
  flight.release()
  assert.equal(flight.axes().pitch, 0)
})

test("simultaneous pitch, yaw, and roll; last pitch press wins", () => {
  const flight = new FlightControls({send: () => {}, now: () => 1000})
  for (const code of ["KeyW", "KeyD", "KeyQ"]) flight.keyDown(press(code))
  assert.deepEqual(flight.axes(), {yaw: 1, pitch: 1, roll: -1})
  for (const code of ["KeyS", "KeyA", "KeyE"]) flight.keyDown(press(code))
  assert.deepEqual(flight.axes(), {yaw: 0, pitch: -1, roll: 0})
  flight.keyUp(press("KeyS"))
  flight.keyUp(press("KeyA"))
  flight.keyUp(press("KeyE"))
  assert.deepEqual(flight.axes(), {yaw: 1, pitch: 1, roll: -1})
  flight.keyDown(press("KeyF"))
  assert.deepEqual(flight.axes(), {yaw: 0, pitch: 0, roll: 0})
})

test("= accelerates and - decelerates through zero into reverse while held", () => {
  let time = 1000
  const sent = []
  const flight = new FlightControls({send: p => sent.push(p), now: () => time})

  flight.keyDown(press("Equal"))
  assert.equal(flight.throttle, 0.1)
  for (let i = 0; i < 5; i++) {
    time += 125
    flight.heartbeat(time)
  }
  assert.equal(flight.throttle, 0.6)
  flight.keyUp(press("Equal"))
  time += 125
  flight.keyDown(press("Minus"))
  for (let i = 0; i < 12; i++) {
    time += 125
    flight.heartbeat(time)
  }
  assert.equal(flight.throttle, -0.7)
  flight.keyUp(press("Minus"))
  assert.equal(sent.at(-1).throttle, -0.7)
  assert.deepEqual(flight.axes(), {yaw: 0, pitch: 0, roll: 0})
})

test("throttle clamps, numpad works, and OS key repeat cannot speed up the ramp", () => {
  let time = 1000
  const flight = new FlightControls({send: () => {}, now: () => time})
  flight.keyDown(press("NumpadSubtract"))
  for (let i = 0; i < 20; i++) {
    time += 125
    flight.heartbeat(time)
  }
  assert.equal(flight.throttle, -1)
  flight.keyUp(press("NumpadSubtract"))
  time += 125
  flight.keyDown(press("NumpadAdd"))
  assert.equal(flight.throttle, -0.9)
  for (let i = 0; i < 5; i++) flight.keyDown(press("NumpadAdd", {repeat: true}))
  assert.equal(flight.throttle, -0.9)
  for (let i = 0; i < 25; i++) {
    time += 125
    flight.heartbeat(time)
  }
  assert.equal(flight.throttle, 1)
  flight.keyUp(press("NumpadAdd"))
})

test("unmodified E rolls, Ctrl+E toggles mode without rolling; text inputs protected", () => {
  const sent = []
  const flight = new FlightControls({send: p => sent.push(p), now: () => 2000})
  flight.keyDown(press("KeyE"))
  assert.equal(flight.axes().roll, 1)
  flight.keyUp(press("KeyE"))
  assert.equal(flight.axes().roll, 0)
  flight.keyDown(press("KeyE", {ctrlKey: true}))
  assert.equal(flight.mode, "newtonian")
  assert.equal(flight.axes().roll, 0)
  flight.keyDown(press("KeyE", {ctrlKey: true, repeat: true}))
  assert.equal(flight.mode, "newtonian")
  assert.equal(flight.keyDown(press("KeyW", {target: {tagName: "INPUT"}})), false)
  assert.deepEqual(flight.axes(), {yaw: 0, pitch: 0, roll: 0})
  assert.equal(flight.throttle, 0)
  assert.equal(sent.at(-1).mode, "newtonian")
})

test("held rotation heartbeats, focus loss releases, atlas release remains silent", () => {
  let time = 2000
  const sent = []
  const flight = new FlightControls({send: p => sent.push(p), now: () => time})
  flight.keyDown(press("KeyA"))
  assert.equal(sent.length, 1)
  time += 310
  flight.heartbeat(time)
  assert.equal(sent.length, 2)
  flight.release()
  assert.equal(sent.at(-1).yaw, 0)
  flight.keyDown(press("KeyQ"))
  const count = sent.length
  flight.release({silent: true})
  assert.equal(sent.length, count)
  assert.deepEqual(flight.axes(), {yaw: 0, pitch: 0, roll: 0})
})

test("F releases attitude controls without cancelling held throttle", () => {
  let time = 2000
  const flight = new FlightControls({send: () => {}, now: () => time})
  flight.keyDown(press("Equal"))
  flight.keyDown(press("KeyQ"))
  assert.equal(flight.axes().roll, -1)
  const throttleBefore = flight.throttle
  flight.keyDown(press("KeyF"))
  assert.equal(flight.axes().roll, 0)
  time += 150
  flight.heartbeat(time)
  assert.ok(flight.throttle > throttleBefore)
  flight.keyUp(press("Equal"))
})

const wheel = (deltaY, extras = {}) => ({
  deltaY, deltaMode: 0, defaultPrevented: false,
  preventDefault() { this.prevented = true },
  ...extras,
})

test("mouse wheel sets persistent 5% target throttle while server owns actual speed", () => {
  let time = 1000
  const sent = []
  const flight = new FlightControls({send: data => sent.push(data), now: () => time})
  const ahead = wheel(-100)
  assert.equal(flight.wheel(ahead), true)
  assert.equal(ahead.prevented, true)
  assert.equal(flight.throttle, 0.05)
  assert.equal(sent.at(-1).throttle, 0.05)

  time += 300
  flight.wheel(wheel(-100))
  assert.equal(flight.throttle, 0.1)
  assert.equal(flight.pressed.size, 0)

  time += 300
  flight.wheel(wheel(100))
  assert.equal(flight.throttle, 0.05)
  // Releasing the wheel changes nothing: throttle is a latched target.
  flight.heartbeat(time + 1000)
  assert.equal(flight.throttle, 0.05)
})

test("wheel accumulates trackpad deltas, normalizes Firefox line events and clamps", () => {
  let time = 1000
  const sent = []
  const flight = new FlightControls({send: data => sent.push(data), now: () => time})
  for (let i = 0; i < 7; i++) {
    time += 10
    flight.wheel(wheel(-10))
  }
  assert.equal(flight.throttle, 0)
  flight.wheel(wheel(-10))
  assert.equal(flight.throttle, 0.05)

  time += 300
  flight.wheel(wheel(-3, {deltaMode: 1}))
  assert.equal(flight.throttle, 0.1)
  time += 300
  flight.wheel(wheel(-10_000))
  assert.equal(flight.throttle, 0.25)

  for (let i = 0; i < 40; i++) {
    time += 300
    flight.wheel(wheel(-120))
  }
  assert.equal(flight.throttle, 1)
  for (let i = 0; i < 60; i++) {
    time += 300
    flight.wheel(wheel(120))
  }
  assert.equal(flight.throttle, -1)
})

test("wheel never changes speed over Atlas, text fields, or modified gestures", () => {
  let active = false
  const sent = []
  const flight = new FlightControls({send: data => sent.push(data), active: () => active})
  assert.equal(flight.wheel(wheel(-120)), false)
  active = true
  for (const extras of [
    {target: {tagName: "INPUT"}},
    {target: {isContentEditable: true}},
    {ctrlKey: true}, {metaKey: true}, {shiftKey: true},
    {defaultPrevented: true}, {deltaY: Infinity},
  ]) {
    const event = wheel(-120, extras)
    assert.equal(flight.wheel(event), false)
    assert.equal(event.prevented, undefined)
  }
  assert.equal(flight.throttle, 0)
  assert.equal(sent.length, 0)
})
