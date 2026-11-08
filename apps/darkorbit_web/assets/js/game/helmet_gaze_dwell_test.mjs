import test from "node:test"
import assert from "node:assert/strict"
import {HelmetGazeDwell} from "./helmet_gaze_dwell.mjs"

test("one second hold to arm, then 800ms circular confirmation, only one activation", () => {
  const dwell = new HelmetGazeDwell()
  assert.equal(dwell.update("nav_open", 100).progress, 0)
  assert.equal(dwell.update("nav_open", 1_099).armed, false)
  const armed = dwell.update("nav_open", 1_100)
  assert.equal(armed.armed, true)
  assert.equal(armed.progress, 0)
  assert.equal(dwell.update("nav_open", 1_500).progress, 0.5)
  assert.equal(dwell.update("nav_open", 1_899).activated, null)
  assert.equal(dwell.update("nav_open", 1_900).activated, "nav_open")
  assert.equal(dwell.update("nav_open", 2_900).activated, null)
})

test("looking away, losing tracking, changing target or clock rollback cancels", () => {
  const dwell = new HelmetGazeDwell()
  dwell.update("nav_open", 0)
  assert.equal(dwell.update("nav_open", 1_600).progress, 0.75)
  assert.equal(dwell.update(null, 1_650).progress, 0)
  assert.equal(dwell.update("nav_open", 1_700).progress, 0)
  assert.equal(dwell.update("nav_close", 3_200).progress, 0)
  assert.equal(dwell.update("nav_close", 5_000).activated, "nav_close")
  assert.equal(dwell.update("nav_close", 6_000).activated, null)
  dwell.update("nav_open", 7_000)
  assert.equal(dwell.update("nav_open", 8_799, false).activated, null)
  assert.equal(dwell.update("nav_open", 8_800).progress, 0)
  assert.equal(dwell.update("nav_open", 8_700).progress, 0)
})
