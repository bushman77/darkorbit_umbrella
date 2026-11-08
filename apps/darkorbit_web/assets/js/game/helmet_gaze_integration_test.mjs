import test from "node:test"
import assert from "node:assert/strict"
import {readFileSync} from "node:fs"
const js = name => readFileSync(new URL(name, import.meta.url), "utf8")
const phone = readFileSync(new URL(
  "../../../lib/darkorbit_web/controllers/helmet_html/show.html.heex", import.meta.url), "utf8")
const view = js("./stereo_view.js")
const helmet = js("./helmet_client.mjs")
const gaze = js("./helmet_gaze_dwell.mjs")

test("cockpit remains anchored to ship rather than following the HMD head", () => {
  assert.match(view, /this\.cockpitFraming\s*=\s*framing/)
  assert.match(view, /this\.scene\.add\(framing\)/)
  assert.match(view, /this\.cockpitFraming\.position\.copy\(this\.camera\.position\)/)
  assert.match(view, /this\.cockpitFraming\.quaternion\.copy\(this\.camera\.quaternion\)/)
  assert.match(view, /this\.camera\.quaternion\.multiply\(this\.helmetHeadRotation\)/)
  assert.doesNotMatch(view, /this\.camera\.add\(framing\)/)
})

test("helmet has explicit sensor permission, read-only local controls and recenter", () => {
  assert.match(phone, /id="helmet-enable-tracking"/)
  assert.match(phone, /id="helmet-recenter-tracking"/)
  assert.match(phone, /id="helmet-tracking-status"/)
  assert.match(helmet, /new HelmetHeadTracking\(/)
  assert.match(helmet, /new HelmetGazeDwell\(/)
  assert.match(helmet, /this\.view\.setHelmetHeadRotation\(this\.headTracking\.rotation\(time\)\)/)
  assert.match(helmet, /update\.activated === "nav_open"/)
  assert.match(helmet, /update\.activated === "nav_close"/)
  assert.match(helmet, /update\.activated === "recenter"/)
  assert.match(view, /this\.setHelmetNavOpen\(this\.helmetGazeEnabled && this\.helmetNavOpen\)/)
  assert.match(view, /this\.raycaster\.intersectObjects\(/)
  assert.match(view, /this\.helmetNavRecenter/)
  assert.match(view, /this\.camera\.add\(this\.gazeArc\)/)
  assert.match(gaze, /GAZE_ARM_MS = 1_000/)
  assert.match(gaze, /GAZE_CONFIRM_MS = 800/)
  assert.doesNotMatch(helmet, /channel\.push\("station_dock"|"station_launch"|"flight_controls"/)
})
