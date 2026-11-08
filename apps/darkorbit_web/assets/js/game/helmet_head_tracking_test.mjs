import test from "node:test"
import assert from "node:assert/strict"
import {HelmetHeadTracking, handsetQuaternion} from "./helmet_head_tracking.mjs"

const near = (a, b, tolerance = 1e-8) => assert.ok(Math.abs(a - b) < tolerance)

test("Euler/device quaternion stays unit length and screen orientation changes it", () => {
  const q = handsetQuaternion({alpha: 35, beta: 20, gamma: -8}, 90)
  assert.ok(q)
  near(Math.hypot(q.x, q.y, q.z, q.w), 1)
  assert.notDeepEqual(q, handsetQuaternion({alpha: 35, beta: 20, gamma: -8}, 0))
  assert.equal(handsetQuaternion({alpha: NaN, beta: 0, gamma: 0}), null)
})

function fakePhone({secure = true, hasSensor = true, permission = null} = {}) {
  const listeners = new Map()
  const win = {
    isSecureContext: secure,
    screen: {orientation: {angle: 90}},
    DeviceOrientationEvent: hasSensor ? (permission === null ? function Event(){} :
      {requestPermission: () => permission}) : undefined,
    addEventListener: (name, cb) => listeners.set(name, cb),
    removeEventListener: name => listeners.delete(name),
  }
  return {win, emit: data => listeners.get("deviceorientation")?.(data),
    hasListener: () => listeners.has("deviceorientation")}
}

test("requires a secure sensor-capable phone; denied permission is safe", async () => {
  for (const opts of [{secure: false}, {hasSensor: false},
    {permission: Promise.resolve("denied")}]) {
    const phone = fakePhone(opts)
    const tracking = new HelmetHeadTracking({win: phone.win})
    await tracking.startFromGesture()
    assert.equal(tracking.ready(), false)
    assert.equal(phone.hasListener(), false)
  }
})

test("calibrates present head direction, tracks relative yaw, recenters, times out", async () => {
  let time = 100
  const phone = fakePhone()
  const status = []
  const tracking = new HelmetHeadTracking({
    win: phone.win, now: () => time, onStatus: state => status.push(state),
  })
  assert.equal(await tracking.startFromGesture(), "waiting")
  phone.emit({alpha: 15, beta: 30, gamma: 0})
  assert.equal(tracking.status, "tracking")
  const neutral = tracking.rotation()
  near(neutral.x, 0)
  near(neutral.y, 0)
  near(neutral.z, 0)
  near(neutral.w, 1)
  time = 200
  phone.emit({alpha: 50, beta: 30, gamma: 0})
  const rotation = tracking.rotation()
  assert.ok(Math.abs(rotation.y) + Math.abs(rotation.x) + Math.abs(rotation.z) > 0.05)
  near(Math.hypot(rotation.x, rotation.y, rotation.z, rotation.w), 1)
  assert.ok(tracking.recenter())
  const neutral = tracking.rotation()
  near(neutral.x, 0)
  near(neutral.y, 0)
  near(neutral.z, 0)
  near(neutral.w, 1)
  assert.equal(tracking.rotation(2_300), null)
  tracking.stop()
  assert.equal(phone.hasListener(), false)
  assert.equal(tracking.rotation(), null)
  assert.deepEqual(status, ["waiting", "tracking", "off"])
})
