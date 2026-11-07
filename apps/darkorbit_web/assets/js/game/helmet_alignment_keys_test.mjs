import test from "node:test"
import assert from "node:assert/strict"
import {
  helmetAlignmentKeyIntent as intent,
  helmetAlignmentShortcut as shortcut,
  HelmetAlignmentKeyGate,
} from "./helmet_alignment_keys.mjs"

test("one press of left/right changes lens spacing, never a held repeat", () => {
  assert.deepEqual(intent({code: "ArrowLeft"}, {active: true}), {axis: "gap", direction: -1})
  assert.deepEqual(intent({code: "ArrowRight"}, {active: true}), {axis: "gap", direction: 1})
  assert.deepEqual(intent({key: "ArrowLeft"}, {active: true}), {axis: "gap", direction: -1})
  assert.equal(intent({code: "ArrowLeft", repeat: true}, {active: true}), null)
  assert.equal(intent({code: "ArrowRight", repeat: true}, {active: true}), null)
})

test("F6 and Ctrl+F6 change simulated eye separation once per press", () => {
  assert.deepEqual(intent({code: "F6"}, {active: true}), {axis: "eye_sep", direction: -1})
  assert.deepEqual(intent({code: "F6", ctrlKey: true}, {active: true}), {axis: "eye_sep", direction: 1})
  assert.equal(intent({code: "F6", repeat: true}, {active: true}), null)
  assert.equal(intent({code: "F5"}, {active: true}), null)
})

test("Atlas, text input, modifiers and unrelated keys are never intercepted", () => {
  for (const [event, options] of [
    [{code: "ArrowLeft"}, {active: false}],
    [{code: "ArrowRight"}, {active: true, typing: true}],
    [{code: "ArrowLeft", ctrlKey: true}, {active: true}],
    [{code: "ArrowRight", altKey: true}, {active: true}],
    [{code: "ArrowLeft", shiftKey: true}, {active: true}],
    [{code: "ArrowRight", metaKey: true}, {active: true}],
    [{code: "ArrowLeft", defaultPrevented: true}, {active: true}],
    [{code: "F7"}, {active: true}],
  ]) {
    assert.equal(intent(event, options), null)
    assert.equal(shortcut(event, options), false)
  }
})

test("every repeat is reserved from browser scrolling even when there is no adjustment", () => {
  const gate = new HelmetAlignmentKeyGate()
  const opts = {active: true}
  assert.deepEqual(gate.keyDown({code: "ArrowLeft"}, opts),
    {reserved: true, intent: {axis: "gap", direction: -1}})
  assert.deepEqual(gate.keyDown({code: "ArrowLeft", repeat: true}, opts),
    {reserved: true, intent: null})
  // Some keyboard sources emit duplicate keydown without the repeat flag.
  assert.deepEqual(gate.keyDown({code: "ArrowLeft"}, opts),
    {reserved: true, intent: null})
  gate.keyUp({code: "ArrowLeft"})
  assert.deepEqual(gate.keyDown({code: "ArrowLeft"}, opts),
    {reserved: true, intent: {axis: "gap", direction: -1}})
  assert.deepEqual(gate.keyDown({code: "ArrowRight"}, opts),
    {reserved: true, intent: {axis: "gap", direction: 1}})
  gate.release()
  assert.deepEqual(gate.keyDown({code: "ArrowRight"}, opts),
    {reserved: true, intent: {axis: "gap", direction: 1}})
  assert.deepEqual(gate.keyDown({code: "ArrowLeft"}, {active: false}),
    {reserved: false, intent: null})
})

test("F6 and Ctrl+F6 reserve focus-changing browser shortcuts even on hold", () => {
  const gate = new HelmetAlignmentKeyGate()
  assert.deepEqual(gate.keyDown({code: "F6", ctrlKey: true}, {active: true}),
    {reserved: true, intent: {axis: "eye_sep", direction: 1}})
  assert.deepEqual(gate.keyDown({code: "F6", ctrlKey: true, repeat: true}, {active: true}),
    {reserved: true, intent: null})
  gate.keyUp({code: "F6"})
  assert.deepEqual(gate.keyDown({code: "F6"}, {active: true}),
    {reserved: true, intent: {axis: "eye_sep", direction: -1}})
})
