import test from "node:test"
import assert from "node:assert/strict"
import {readFileSync} from "node:fs"
import {
  stereoViewports, inwardStereoProjectionOffset, applyTransientStereoOffset,
} from "./stereo_viewport.mjs"

test("equal landscape eyes do not overlap and retain correct per-eye aspect", () => {
  const layout = stereoViewports(2400, 1080, 0)
  assert.deepEqual(layout.left, {x: 0, y: 0, width: 1200, height: 1080})
  assert.deepEqual(layout.right, {x: 1200, y: 0, width: 1200, height: 1080})
  assert.equal(layout.eyeAspect, 1200 / 1080)
})

test("optical gap separates two equal-size views without overlap", () => {
  const layout = stereoViewports(2400, 1080, 40)
  assert.equal(layout.left.width, 1180)
  assert.equal(layout.right.x, 1220)
  assert.equal(layout.right.width, 1180)
  assert.equal(layout.gap, 40)
  assert.equal(layout.left.x + layout.left.width + layout.gap, layout.right.x)
  assert.equal(layout.right.x + layout.right.width, 2400)
})

test("odd-width and extreme inputs never overlap the eye viewports", () => {
  for (const width of [3, 1001, 2341]) {
    const layout = stereoViewports(width, 800, 44)
    assert.ok(layout.left.width > 0)
    assert.ok(layout.right.width > 0)
    assert.ok(layout.left.width + layout.gap <= layout.right.x)
    assert.equal(layout.right.x + layout.right.width, width)
    assert.ok(Math.abs(layout.left.width - layout.right.width) <= 1)
  }
})

test("negative center alignment shifts both eye projections inward without overlapping viewports", () => {
  const viewports = stereoViewports(1080, 420, -60)
  assert.equal(viewports.gap, 0)
  assert.equal(viewports.left.width, 540)
  assert.equal(viewports.left.width, viewports.right.x)
  assert.equal(viewports.right.x + viewports.right.width, 1080)

  // A signed gap of -60 shifts each view in by 30 pixels:
  // 30px / 540px * 2 = 1/9 of normalized device coordinates.
  assert.ok(Math.abs(inwardStereoProjectionOffset(-60, viewports.left.width) - 1 / 9) < 1e-12)
  assert.equal(inwardStereoProjectionOffset(0, viewports.left.width), 0)
  assert.equal(inwardStereoProjectionOffset(40, viewports.left.width), 0)
  assert.equal(inwardStereoProjectionOffset(-2, viewports.left.width), 2 / 540)
})

test("stationary SBS picture does not drift across 10,000 frames with negative stored gap", () => {
  const left = {elements: new Float64Array(16)}
  const right = {elements: new Float64Array(16)}
  left.elements[8] = -0.042
  right.elements[8] = 0.042
  const baseL = left.elements[8]
  const baseR = right.elements[8]
  const gap = -60
  const shift = inwardStereoProjectionOffset(gap, 540)

  for (let frame = 0; frame < 10_000; frame++) {
    const restore = applyTransientStereoOffset(left, right, gap, 540)
    // This value must be EXACTLY the same on every stationary frame.
    assert.ok(Math.abs(left.elements[8] - (baseL - shift)) < 1e-12)
    assert.ok(Math.abs(right.elements[8] - (baseR + shift)) < 1e-12)
    restore()
    assert.equal(left.elements[8], baseL)
    assert.equal(right.elements[8], baseR)
  }
})

test("changing calibration stays finite, independent and idempotent", () => {
  const left = {elements: new Float64Array(16)}
  const right = {elements: new Float64Array(16)}
  left.elements[8] = -0.0125
  right.elements[8] = 0.0125
  for (const gap of [-160, -80, -60, -2, 0, 8, 80, -160]) {
    const restore = applyTransientStereoOffset(left, right, gap, 500)
    const shift = inwardStereoProjectionOffset(gap, 500)
    assert.ok(Math.abs(left.elements[8] - (-0.0125 - shift)) < 1e-12)
    assert.ok(Math.abs(right.elements[8] - (0.0125 + shift)) < 1e-12)
    restore()
    restore() // cleanup is safe if called twice
    assert.equal(left.elements[8], -0.0125)
    assert.equal(right.elements[8], 0.0125)
  }
})

test("positive gap never alters the projection matrix", () => {
  const left = {elements: new Float32Array(16)}
  const right = {elements: new Float32Array(16)}
  left.elements[8] = -0.04
  right.elements[8] = 0.04
  const baselineL = left.elements[8]
  const baselineR = right.elements[8]
  const restore = applyTransientStereoOffset(left, right, 60, 430)
  assert.equal(left.elements[8], baselineL)
  assert.equal(right.elements[8], baselineR)
  restore()
})

test("SBS renderer restores projection even if WebGL rendering fails", () => {
  const fs = requireReadSource()
  assert.match(fs, /const restore = applyTransientStereoOffset\(/)
  assert.match(fs, /\} finally \{\s*restore\(\)/)
  assert.doesNotMatch(fs, /projectionMatrix\.elements\[8\]\s*[+\-]=/)
})

function requireReadSource() {
  return readFileSync(new URL("./stereo_view.js", import.meta.url), "utf8")
}
