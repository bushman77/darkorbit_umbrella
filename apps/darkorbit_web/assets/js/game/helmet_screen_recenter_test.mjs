import test from "node:test"
import assert from "node:assert/strict"
import {headsetScreenTapRecenterAllowed as allowed} from "./helmet_screen_recenter.mjs"

const canvas = {closest: () => null}
const controls = {closest: () => ({id: "helmet-fullscreen"})}
const active = {mode: "combat", immersiveReady: true, running: true,
  setupVisible: false, target: canvas}

test("a screen stylus tap centers only the running immersive cockpit", () => {
  assert.equal(allowed(active), true)
  assert.equal(allowed({...active, mode: "standby"}), false)
  assert.equal(allowed({...active, immersiveReady: false}), false)
  assert.equal(allowed({...active, running: false}), false)
  assert.equal(allowed({...active, setupVisible: true}), false)
  assert.equal(allowed({...active, target: null}), false)
})

test("setup controls and future interactive elements must not recenter", () => {
  assert.equal(allowed({...active, target: controls}), false)
  assert.equal(allowed({...active, target: {}}), true)
})
