import assert from "node:assert/strict"
import test from "node:test"

import {
  applyAuthoritativeDamage,
  findNpcAtScreenPoint,
  healthPercent,
  nearestNpc,
  selectableNpc,
} from "./combat_client.mjs"

const npc = (id, x, y, overrides = {}) => ({
  id,
  kind: "npc",
  status: "alive",
  hull: 800,
  maxHull: 800,
  shields: 400,
  maxShields: 400,
  target: {x, y},
  render: {x, y},
  ...overrides,
})

test("target helpers select only live NPCs and break equal distances deterministically", () => {
  const entities = [
    {id: "player", kind: "player", status: "alive", hull: 4_000, target: {x: 1, y: 1}},
    npc("npc:b", 10, 0),
    npc("npc:a", -10, 0),
    npc("npc:destroyed", 1, 0, {status: "destroyed", hull: 0}),
  ]

  assert.equal(selectableNpc(entities[0]), false)
  assert.equal(selectableNpc(entities[1]), true)
  assert.equal(selectableNpc(entities[3]), false)
  assert.equal(nearestNpc(entities, {x: 0, y: 0}).id, "npc:a")
})

test("NPC hit testing uses rendered screen positions and entity dimensions", () => {
  const entities = [npc("npc:near", 100, 100), npc("npc:far", 250, 250)]
  const worldToScreen = position => ({x: position.x - 20, y: position.y - 10})
  const dimensions = () => ({width: 60, height: 40})

  assert.equal(
    findNpcAtScreenPoint(entities, {x: 82, y: 88}, worldToScreen, dimensions).id,
    "npc:near"
  )
  assert.equal(findNpcAtScreenPoint(entities, {x: 111, y: 90}, worldToScreen, dimensions), null)
  assert.equal(findNpcAtScreenPoint(entities, {x: 80, y: 111}, worldToScreen, dimensions), null)
})

test("health percentages clamp and authoritative damage never uses local guesses", () => {
  assert.equal(healthPercent(50, 200), 25)
  assert.equal(healthPercent(-10, 200), 0)
  assert.equal(healthPercent(500, 200), 100)
  assert.equal(healthPercent(10, 0), 0)

  const target = npc("npc:one", 0, 0)
  assert.equal(
    applyAuthoritativeDamage(target, {
      id: "npc:one",
      hull: 730,
      max_hull: 800,
      shields: 120,
      max_shields: 400,
      status: "alive",
    }),
    true
  )
  assert.equal(target.hull, 730)
  assert.equal(target.shields, 120)

  assert.equal(applyAuthoritativeDamage(target, {id: "npc:other", hull: 0}), false)
  assert.equal(target.hull, 730)
})
