import test from "node:test"
import assert from "node:assert/strict"
import {HelmetScreenWake} from "./helmet_screen_wake.mjs"

function fakeLock() {
  const callbacks = []
  return {
    released: false,
    addEventListener(name, callback) {
      if (name === "release") callbacks.push(callback)
    },
    async release() {
      if (this.released) return
      this.released = true
      for (const callback of callbacks) callback()
    },
  }
}

test("explicit HMD activation keeps screen awake and foreground reacquires it", async () => {
  let visible = true
  const locks = []
  const wake = new HelmetScreenWake({
    wakeLock: {request(type) {
      assert.equal(type, "screen")
      const lock = fakeLock()
      locks.push(lock)
      return Promise.resolve(lock)
    }},
    visible: () => visible,
  })
  assert.equal(await wake.acquire(), false)
  assert.equal(locks.length, 0)
  assert.equal(await wake.enable(), true)
  assert.equal(locks.length, 1)
  assert.equal(await wake.acquire(), true)
  assert.equal(locks.length, 1)

  visible = false
  await wake.onVisibilityChange()
  assert.equal(locks[0].released, true)
  assert.equal(await wake.acquire(), false)
  assert.equal(locks.length, 1)

  visible = true
  assert.equal(await wake.onVisibilityChange(), true)
  assert.equal(locks.length, 2)
  await wake.disable()
  assert.equal(locks[1].released, true)
  assert.equal(await wake.acquire(), false)
  assert.equal(locks.length, 2)
})

test("unsupported or denied Android wake locks fail safely without disabling SBS", async () => {
  assert.equal(await new HelmetScreenWake({wakeLock: null}).enable(), false)
  assert.equal(await new HelmetScreenWake({
    wakeLock: {request: () => Promise.reject(new Error("insecure context"))},
  }).enable(), false)
})

test("unexpected screen lock release can request a bounded recovery", async () => {
  const callbacks = []
  const locks = []
  const wake = new HelmetScreenWake({
    wakeLock: {request() {
      const lock = fakeLock()
      locks.push(lock)
      return Promise.resolve(lock)
    }},
    visible: () => true,
    schedule: callback => callbacks.push(callback),
  })
  await wake.enable()
  await locks[0].release()
  assert.equal(callbacks.length, 1)
  callbacks.shift()()
  await Promise.resolve()
  await Promise.resolve()
  assert.equal(locks.length, 2)
  await wake.disable()
})
