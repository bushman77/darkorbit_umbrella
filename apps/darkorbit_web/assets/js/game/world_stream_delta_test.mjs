import test from "node:test"
import assert from "node:assert/strict"
import {WorldStreamDelta} from "./world_stream_delta.mjs"

const initial = () => ({
  tick: 10, tick_ms: 100, map_id: "sol:earth", planetary_warnings: [],
  entities: [
    {id: 1, kind: "player", hull: 200, max_hull: 300, position_3d: {x: 1, y: 2, z: 3}},
    {id: "scow", kind: "npc", hull: 210, ship_class: "scow"}
  ]
})

test("patch retains static attributes and updates movement", () => {
  const stream = new WorldStreamDelta(initial())
  const map = stream.apply({
    base_tick: 10, tick: 11, entities: [{id: 1, position_3d: {x: 9, y: 2, z: 3}}],
    removed: [], changes: {}
  })
  assert.equal(map.entities[0].hull, 200)
  assert.equal(map.entities[0].position_3d.x, 9)
  assert.equal(map.entities[1].ship_class, "scow")
})

test("removals, spawns and metadata changes", () => {
  const stream = new WorldStreamDelta(initial())
  const map = stream.apply({
    base_tick: 10, tick: 11, entities: [{id: "dart", kind: "npc", hull: 40}],
    removed: ["scow"], changes: {planetary_warnings: [{entity_id: 1}]}
  })
  assert.deepEqual(map.entities.map(x => x.id), [1, "dart"])
  assert.deepEqual(map.planetary_warnings, [{entity_id: 1}])
})

test("missed ticks require resync and do not mutate baseline", () => {
  const stream = new WorldStreamDelta(initial())
  assert.equal(stream.apply({base_tick: 9, tick: 11, entities: [], removed: [], changes: {}}), null)
  assert.equal(stream.map.tick, 10)
  assert.equal(stream.apply({base_tick: 10, tick: 11, entities: [{id: "unknown"}], removed: [], changes: {}}), null)
  assert.equal(stream.map.tick, 10)
  stream.reset({...initial(), tick: 20})
  assert.equal(stream.map.tick, 20)
})

test("movement preview does not corrupt tick baseline", () => {
  const stream = new WorldStreamDelta(initial())
  const preview = stream.previewEntity({id: 1, position_3d: {x: 99, y: 2, z: 3}})
  assert.equal(preview.hull, 200)
  assert.equal(preview.position_3d.x, 99)
  assert.equal(stream.map.entities[0].position_3d.x, 1)
  const map = stream.apply({base_tick: 10, tick: 11, entities: [], removed: [], changes: {}})
  assert.equal(map.entities[0].position_3d.x, 1)
})
