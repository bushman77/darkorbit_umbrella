import test from "node:test"
import assert from "node:assert/strict"
import {stereoViewports} from "./stereo_viewport.mjs"

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
