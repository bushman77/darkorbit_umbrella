import assert from "node:assert/strict"
import test from "node:test"
import {npcVisualClass} from "./ship_model_selection.mjs"

test("server-spawned Harbor Scow renders as Scow on laptop and headset", () => {
  assert.equal(npcVisualClass("solar-scow-735", "scow"), "scow")
  assert.equal(npcVisualClass("scow"), "scow")
  assert.equal(npcVisualClass(null, "scow"), "scow")
})

test("combat fighters keep Dart graphics and cannot masquerade as Scows", () => {
  assert.equal(npcVisualClass("solar-dart-22", "scow"), "dart")
  assert.equal(npcVisualClass("solar-scow-22", "dart"), "scow")
  assert.equal(npcVisualClass("dart", "dart"), "dart")
  assert.equal(npcVisualClass("strange-type", null), "generic")
  assert.equal(npcVisualClass(null, "bogus"), "generic")
})
