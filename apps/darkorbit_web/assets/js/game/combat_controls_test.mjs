import assert from "node:assert/strict"
import test from "node:test"

import {
  combatKeyIntent,
  gameplayTypingTarget,
  manualLaserPointerIntent,
  desiredEntityAngle,
  hotbarActionActive,
  hotbarSlotForCode,
  smoothAngle,
} from "./combat_controls.mjs"

test("number-row keys map slots 1 through 0 without per-slot command logic", () => {
  const codes = [
    "Digit1",
    "Digit2",
    "Digit3",
    "Digit4",
    "Digit5",
    "Digit6",
    "Digit7",
    "Digit8",
    "Digit9",
    "Digit0",
  ]

  assert.deepEqual(codes.map(hotbarSlotForCode), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
  assert.equal(hotbarSlotForCode("Numpad1"), null)
})

test("Ctrl toggles once from either physical key and ignores held repeats or chords", () => {
  assert.deepEqual(
    combatKeyIntent({code: "ControlLeft", ctrlKey: true}),
    {type: "toggle_laser"}
  )
  assert.deepEqual(
    combatKeyIntent({code: "ControlRight", ctrlKey: true}),
    {type: "toggle_laser"}
  )
  assert.equal(combatKeyIntent({code: "ControlLeft", ctrlKey: true, repeat: true}), null)
  assert.equal(combatKeyIntent({code: "Digit1", ctrlKey: true}), null)
  assert.equal(combatKeyIntent({code: "KeyA", ctrlKey: true}), null)
  assert.equal(combatKeyIntent({code: "ControlRight", ctrlKey: true, shiftKey: true}), null)
})

test("right mouse button fires only while combat is active, Space is unassigned", () => {
  const event = (button, extras = {}) => ({button, ...extras})
  assert.equal(manualLaserPointerIntent(event(2), true), true)
  assert.equal(manualLaserPointerIntent(event(2), false), false)
  assert.equal(manualLaserPointerIntent(event(0), true), false)
  assert.equal(manualLaserPointerIntent(event(1), true), false)
  assert.equal(manualLaserPointerIntent(event(2, {ctrlKey: true}), true), false)
  assert.equal(manualLaserPointerIntent(event(2, {altKey: true}), true), false)
  assert.equal(manualLaserPointerIntent(event(2, {metaKey: true}), true), false)
  assert.equal(manualLaserPointerIntent(event(2, {shiftKey: true}), true), false)
  assert.equal(combatKeyIntent({code: "Space"}), null)
  assert.equal(combatKeyIntent({code: "Space", repeat: true}), null)
  assert.deepEqual(combatKeyIntent({code: "KeyL"}), {type: "toggle_laser"})
  assert.deepEqual(combatKeyIntent({code: "KeyT"}), {type: "target_nearest"})
  assert.equal(combatKeyIntent({code: "KeyL", repeat: true}), null)
  assert.equal(combatKeyIntent({code: "KeyT", target: {matches: () => true}}), null)
  assert.deepEqual(combatKeyIntent({code: "Escape"}), {type: "disengage"})
  assert.deepEqual(combatKeyIntent({code: "Digit0"}), {type: "activate_slot", slot: 10})
  assert.equal(combatKeyIntent({code: "Digit1", repeat: true}), null)
  assert.equal(combatKeyIntent({code: "Digit1", ctrlKey: true}), null)
  assert.equal(combatKeyIntent({code: "Digit1", target: {matches: () => true}}), null)
  assert.equal(gameplayTypingTarget({tagName: "INPUT"}), true)
})

test("toggle action metadata drives the active hotbar state without a slot special case", () => {
  assert.equal(
    hotbarActionActive({type: "ammunition", activationMode: "toggle"}, true),
    true
  )
  assert.equal(
    hotbarActionActive({type: "ammunition", activationMode: "toggle"}, false),
    false
  )
  assert.equal(
    hotbarActionActive({type: "rocket", activationMode: "single_use"}, true),
    false
  )
  assert.equal(hotbarActionActive(null, true), false)
})

test("engaged target facing overrides movement and follows target movement", () => {
  const ship = {
    id: "pilot",
    render: {x: 10, y: 10},
    navigationAngle: Math.PI,
    angle: Math.PI,
    engagedTargetId: "npc:one",
  }
  const target = {id: "npc:one", render: {x: 110, y: 10}}
  const entities = new Map([[ship.id, ship], [target.id, target]])

  assert.equal(desiredEntityAngle(ship, entities), 0)
  target.render = {x: 10, y: 110}
  assert.equal(desiredEntityAngle(ship, entities), Math.PI / 2)

  ship.engagedTargetId = null
  assert.equal(desiredEntityAngle(ship, entities), Math.PI)
})

test("rotation interpolation takes the shortest path without angle wrap jitter", () => {
  const current = Math.PI - 0.1
  const desired = -Math.PI + 0.1
  const halfway = smoothAngle(current, desired, 0.5)

  assert.ok(halfway > current)
  assert.ok(Math.abs(halfway - Math.PI) < 0.000_001)
})

test("NPC Dart turns toward its target during attack even when stationary", () => {
  const npc = {
    id: "npc:1-1:dart:1", kind: "npc", targetId: "pilot",
    render: {x: 1500, y: 1000}, angle: 0,
  }
  const pilot = {id: "pilot", render: {x: 1200, y: 1000}}
  assert.equal(desiredEntityAngle(npc, new Map([["pilot", pilot]])), Math.PI)
})
