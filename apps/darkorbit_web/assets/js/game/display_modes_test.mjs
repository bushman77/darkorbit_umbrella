import assert from "node:assert/strict"
import test from "node:test"
import {FLIGHT_DISPLAY_MODES, validFlightMode, nextFlightMode} from "./display_modes.mjs"

test("the cockpit has exactly two flight presentation modes", () => {
  assert.deepEqual(FLIGHT_DISPLAY_MODES, ["3d", "sbs"])
  assert.equal(validFlightMode("3d"), true)
  assert.equal(validFlightMode("sbs"), true)
  assert.equal(validFlightMode("2d"), false)
  assert.equal(validFlightMode("atlas"), false)
})

test("V cycles strictly between 3D and SBS", () => {
  assert.equal(nextFlightMode("3d"), "sbs")
  assert.equal(nextFlightMode("sbs"), "3d")
  let mode = "3d"
  for (let i = 0; i < 50; i++) {
    mode = nextFlightMode(mode)
    assert.ok(validFlightMode(mode))
  }
})
