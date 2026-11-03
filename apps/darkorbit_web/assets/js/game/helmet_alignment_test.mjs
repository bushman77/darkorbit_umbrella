import test from "node:test"
import assert from "node:assert/strict"
import {adjustedHelmetAlignment as adjust} from "./helmet_alignment.mjs"

test("keyboard gap changes by 2 pixels and leaves separation unchanged", () => {
  assert.deepEqual(adjust({eyeGapPx: 8, eyeSepMm: 64}, "gap", -1),
    {eyeGapPx: 6, eyeSepMm: 64})
  assert.deepEqual(adjust({eyeGapPx: 8, eyeSepMm: 64}, "gap", 1),
    {eyeGapPx: 10, eyeSepMm: 64})
})

test("keyboard eye separation changes by 1 mm independently", () => {
  assert.deepEqual(adjust({eyeGapPx: 8, eyeSepMm: 64}, "eye_sep", -1),
    {eyeGapPx: 8, eyeSepMm: 63})
  assert.deepEqual(adjust({eyeGapPx: 8, eyeSepMm: 64}, "eye_sep", 1),
    {eyeGapPx: 8, eyeSepMm: 65})
})

test("calibration clamps at phone UI bounds", () => {
  assert.equal(adjust({eyeGapPx: 0, eyeSepMm: 40}, "gap", -1).eyeGapPx, 0)
  assert.equal(adjust({eyeGapPx: 80, eyeSepMm: 85}, "gap", 1).eyeGapPx, 80)
  assert.equal(adjust({eyeGapPx: 0, eyeSepMm: 40}, "eye_sep", -1).eyeSepMm, 40)
  assert.equal(adjust({eyeGapPx: 80, eyeSepMm: 85}, "eye_sep", 1).eyeSepMm, 85)
  assert.equal(adjust({eyeGapPx: 8, eyeSepMm: 64}, "gap", 2), null)
  assert.equal(adjust({eyeGapPx: 8, eyeSepMm: 64}, "other", 1), null)
})
