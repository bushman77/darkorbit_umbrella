import assert from "node:assert/strict"
import test from "node:test"

import {
  combatKeyIntent,
  desiredEntityAngle,
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

test("combat keys ignore repeat, modifiers, and editable controls", () => {
  const target = selector => ({matches: query => query.includes(selector)})

  assert.deepEqual(combatKeyIntent({code: "Space"}), {type: "engage"})
  assert.deepEqual(combatKeyIntent({code: "Escape"}), {type: "disengage"})
  assert.deepEqual(combatKeyIntent({code: "Digit0"}), {type: "activate_slot", slot: 10})
  assert.equal(combatKeyIntent({code: "Digit1", repeat: true}), null)
  assert.equal(combatKeyIntent({code: "Digit1", ctrlKey: true}), null)
  assert.equal(combatKeyIntent({code: "Digit1", target: target("input")}), null)
  assert.equal(combatKeyIntent({code: "Space", target: {isContentEditable: true}}), null)
  assert.equal(combatKeyIntent({code: "Space", target: target("data-cockpit-drag-handle")}), null)
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
