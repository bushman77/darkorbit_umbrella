import test from "node:test"
import assert from "node:assert/strict"
import {readFileSync} from "node:fs"

const game = readFileSync(
  new URL("../../../lib/darkorbit_web/controllers/game_html/show.html.heex", import.meta.url),
  "utf8",
)
const phone = readFileSync(
  new URL("../../../lib/darkorbit_web/controllers/helmet_html/show.html.heex", import.meta.url),
  "utf8",
)
const desktop = readFileSync(new URL("./client.js", import.meta.url), "utf8")
const viewer = readFileSync(new URL("./helmet_client.mjs", import.meta.url), "utf8")
const control = readFileSync(new URL("./helmet_control.mjs", import.meta.url), "utf8")

test("HMD alignment no longer blocks the cockpit with floating HUD buttons", () => {
  assert.doesNotMatch(game, /id="cockpit-helmet-calibration"/)
  assert.doesNotMatch(game, /data-helmet-axis|data-helmet-direction/)
  assert.match(game, /id="cockpit-helmet-status"/)
  assert.doesNotMatch(control, /data-helmet-axis|updateCalibrationUi/)
})

test("phone has no draggable lens sliders or scroll-causing calibration inputs", () => {
  assert.doesNotMatch(phone, /id="helmet-eye-gap"|id="helmet-eye-sep"/)
  assert.doesNotMatch(phone, /Lens alignment settings/)
  assert.doesNotMatch(viewer, /querySelector\("#helmet-eye-(gap|sep)/)
  assert.match(phone, /laptop keyboard/)
  assert.match(viewer, /this\.rememberCalibration\(\)/)
  assert.match(viewer, /this\.reportAlignment\(\)/)
})

test("only laptop cockpit captures lens shortcuts and cancels browser scroll", () => {
  assert.match(desktop, /this\.helmetAlignmentKeys\.keyDown/)
  assert.match(desktop, /if \(!action\.reserved\) return[\s\S]*?event\.preventDefault\(\)/)
  assert.match(desktop, /this\.helmetAlignmentKeys\.keyUp/)
  assert.match(desktop, /this\.helmetAlignmentKeys\.release\(\)/)
})
