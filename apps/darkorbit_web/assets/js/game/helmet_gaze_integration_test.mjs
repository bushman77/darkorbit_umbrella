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
  assert.match(helmet, /this\.headTracking\.requestRecenter\(\)/)
  assert.match(helmet, /this\.channel\.on\("helmet_recenter"/)
  assert.match(helmet, /this\.root\.addEventListener\("pointerdown", recenterFromScreenTap, true\)/)
  assert.match(helmet, /this\.root\.addEventListener\("click", recenterFromScreenTap, true\)/)
  assert.match(helmet, /this\.recenterFromPilot\(\)/)
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

test("the five-second docking countdown is rendered in both SBS eyes", () => {
  assert.match(view, /this\.updateDockingCountdown\(docked \? null : client\.stationDockingSeconds\)/)
  assert.match(view, /this\.dockingCountdownMesh\.visible = visible/)
  assert.match(view, /this\.dockingCountdownTexture\.needsUpdate = true/)
  assert.match(helmet, /this\.channel\.on\("station_docking_started"/)
  assert.match(helmet, /this\.stationDockingSeconds = this\.docked \? null/)
  assert.doesNotMatch(helmet, /channel\.push\("station_dock"/)
})

test("desktop and SBS render the same server-owned walking pose", () => {
  assert.match(view, /const position = client\.stationPosition/)
  assert.match(view, /this\.camera\.position\.set\(x, 2\.6, z\)/)
  assert.match(view, /this\.camera\.rotation\.set\(0, -yaw, 0, "YXZ"\)/)
  assert.match(view, /this\.camera\.quaternion\.multiply\(this\.helmetHeadRotation\)/)
  assert.match(helmet, /this\.stationPosition = this\.docked \?/)
  assert.doesNotMatch(helmet, /channel\.push\("station_walk"|"station_look"/)
})

test("the 3D docking hangar is driven by server-replicated state, not an HMD command", () => {
  assert.match(view, /const docked = greenStarbaseInteriorVisible\(client\)/)
  assert.match(view, /const activeScene = docked \? this\.hangarScene : this\.scene/)
  assert.match(view, /this\.camera\.quaternion\.multiply\(this\.helmetHeadRotation\)/)
  assert.match(view, /this\.onHelmetGaze\(docked \? null : this\.gazeTarget\(\), time\)/)
  assert.match(helmet, /this\.docked = pilotDockedInWorld\(map, this\.selfId\)/)
  assert.doesNotMatch(helmet, /channel\.push\("station_dock"|"station_launch"/)
})

test("native desktop starts with ALL headset-only meshes hidden", () => {
  // Three.js treats visible=undefined as visible. Initialize opt-in state
  // BEFORE addCockpit creates/synchronizes its meshes, not afterwards.
  const constructor = view.slice(view.indexOf("constructor(canvas)"), view.indexOf("  addStars()"))
  assert.ok(constructor.indexOf("this.helmetGazeEnabled = false") >= 0)
  assert.ok(constructor.indexOf("this.helmetGazeEnabled = false") <
    constructor.indexOf("this.addCockpit()"))
  assert.ok(constructor.indexOf("this.helmetNavOpen = false") <
    constructor.indexOf("this.addCockpit()"))
  assert.ok(constructor.indexOf("this.helmetHeadRotation = null") <
    constructor.indexOf("this.addCockpit()"))
  for (const mesh of ["navSwitch", "helmetNavPanel", "helmetNavClose",
    "helmetNavRecenter", "gazeReticle", "helmetTrackingHint"]) {
    assert.match(view, new RegExp("this\\." + mesh + "\\.visible =\\s*\\n?\\s*Boolean\\("))
  }
  assert.match(view, /this\.setHelmetNavOpen\(false\)/)
  assert.match(view, /this\.setHelmetHeadRotation\(null\)/)
})

test("the phone renders an accessible NAV target and explains missing gyro", () => {
  assert.match(view, /this\.navSwitch\.position\.set\(0\.95, -0\.64, -2\.46\)/)
  assert.match(view, /new THREE\.PlaneGeometry\(2\.00, 1\.08\)/)
  assert.match(view, /ENABLE HEAD TRACKING/)
  assert.match(view, /this\.helmetGazeEnabled && this\.helmetHeadRotation === null/)
})
