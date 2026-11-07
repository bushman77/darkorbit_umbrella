import assert from "node:assert/strict"
import test from "node:test"
import {cockpitHudFit, HUD_GEOMETRY} from "./stereo_layout.mjs"

test("cockpit telemetry remains inside both SBS eye viewports", () => {
  for (const [width, height] of [[1366, 768], [1920, 1080], [2560, 1440], [1024, 768], [720, 1080]]) {
    const fit = cockpitHudFit(width / 2 / height)
    assert.ok(fit.scale > 0 && fit.scale <= 1)
    assert.ok(fit.widthFraction <= 0.751, `cropped horizontally at ${width}x${height}`)
    assert.ok(fit.topFraction > 0.4, `telemetry crowds center at ${width}x${height}`)
    assert.ok(fit.bottomFraction < 0.86, `telemetry cropped below at ${width}x${height}`)
  }
})

test("desktop 3D mode uses the same camera-relative cockpit", () => {
  const fit = cockpitHudFit(16 / 9)
  assert.equal(fit.scale, 1)
  assert.ok(fit.bottomFraction < 0.86)
  assert.equal(HUD_GEOMETRY.width / HUD_GEOMETRY.height > 3.9, true)
})

test("invalid projection parameters fail safely", () => {
  assert.equal(cockpitHudFit(0), null)
  assert.equal(cockpitHudFit(NaN), null)
  assert.equal(cockpitHudFit(1, 180), null)
})
