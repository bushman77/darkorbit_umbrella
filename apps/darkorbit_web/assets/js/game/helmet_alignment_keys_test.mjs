import test from "node:test"
import assert from "node:assert/strict"
import {helmetAlignmentKeyIntent as intent} from "./helmet_alignment_keys.mjs"

test("plain left/right cursor keys move the optical images together/apart", () => {
  assert.deepEqual(intent({code: "ArrowLeft"}, {active: true}), {axis: "gap", direction: -1})
  assert.deepEqual(intent({code: "ArrowRight"}, {active: true}), {axis: "gap", direction: 1})
  assert.deepEqual(intent({key: "ArrowLeft"}, {active: true}), {axis: "gap", direction: -1})
  // Allow throttled arrow repeats for easier live calibration.
  assert.deepEqual(intent({code: "ArrowLeft", repeat: true}, {active: true}),
    {axis: "gap", direction: -1})
})

test("F6 and Ctrl+F6 still adjust eye separation; F5 no longer calibrates", () => {
  assert.deepEqual(intent({code: "F6"}, {active: true}), {axis: "eye_sep", direction: -1})
  assert.deepEqual(intent({code: "F6", ctrlKey: true}, {active: true}), {axis: "eye_sep", direction: 1})
  assert.equal(intent({code: "F5"}, {active: true}), null)
  assert.equal(intent({code: "F5", ctrlKey: true}, {active: true}), null)
})

test("Atlas, typing, modifiers and unrelated keys never calibrate", () => {
  assert.equal(intent({code: "ArrowLeft"}, {active: false}), null)
  assert.equal(intent({code: "ArrowRight"}, {active: true, typing: true}), null)
  assert.equal(intent({code: "ArrowLeft", ctrlKey: true}, {active: true}), null)
  assert.equal(intent({code: "ArrowRight", altKey: true}, {active: true}), null)
  assert.equal(intent({code: "ArrowLeft", shiftKey: true}, {active: true}), null)
  assert.equal(intent({code: "ArrowRight", metaKey: true}, {active: true}), null)
  assert.equal(intent({code: "ArrowLeft", defaultPrevented: true}, {active: true}), null)
  assert.equal(intent({code: "F6", repeat: true}, {active: true}), null)
  assert.equal(intent({code: "F7"}, {active: true}), null)
})
