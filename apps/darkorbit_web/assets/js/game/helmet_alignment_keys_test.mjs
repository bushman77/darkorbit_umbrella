import test from "node:test"
import assert from "node:assert/strict"
import {helmetAlignmentKeyIntent as intent} from "./helmet_alignment_keys.mjs"

test("F5 controls central gap and F6 controls eye separation", () => {
  assert.deepEqual(intent({code: "F5"}, {active: true}), {axis: "gap", direction: -1})
  assert.deepEqual(intent({code: "F5", ctrlKey: true}, {active: true}), {axis: "gap", direction: 1})
  assert.deepEqual(intent({code: "F6"}, {active: true}), {axis: "eye_sep", direction: -1})
  assert.deepEqual(intent({code: "F6", ctrlKey: true}, {active: true}), {axis: "eye_sep", direction: 1})
})

test("hotkeys cannot act from Atlas, text fields, repeats, or other modifiers", () => {
  assert.equal(intent({code: "F5"}, {active: false}), null)
  assert.equal(intent({code: "F5"}, {active: true, typing: true}), null)
  assert.equal(intent({code: "F6", repeat: true}, {active: true}), null)
  assert.equal(intent({code: "F6", shiftKey: true}, {active: true}), null)
  assert.equal(intent({code: "F6", altKey: true}, {active: true}), null)
  assert.equal(intent({code: "F6", metaKey: true}, {active: true}), null)
  assert.equal(intent({code: "F5", defaultPrevented: true}, {active: true}), null)
  assert.equal(intent({code: "F7"}, {active: true}), null)
})
