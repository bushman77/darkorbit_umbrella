import assert from "node:assert/strict"
import test from "node:test"
import {SpaceLaserTrigger} from "./space_laser_trigger.mjs"

const harness = () => {
  let tick = 0
  let next = 0
  let time = 1000
  let active = true
  const shots = []
  const trigger = new SpaceLaserTrigger({
    fire: done => shots.push(done),
    active: () => active,
    worldTick: () => tick,
    nextAttackTick: () => next,
    now: () => time,
  })
  return {
    trigger, shots,
    setTick: n => tick = n, setReady: n => next = n,
    setTime: n => time = n, setActive: n => active = n,
  }
}

test("Space fires on press even without a selected target", () => {
  const h = harness()
  h.trigger.press()
  h.trigger.press()
  h.trigger.update(1000)
  assert.equal(h.shots.length, 1)
  h.setTick(1)
  h.trigger.update(1100)
  assert.equal(h.shots.length, 1)
  h.shots[0](true)
  h.trigger.update(1100)
  assert.equal(h.shots.length, 2)
})

test("holding follows authoritative cooldown, releasing stops future shots", () => {
  const h = harness()
  h.trigger.press()
  assert.equal(h.shots.length, 1)
  h.shots[0](true)
  h.setReady(7)
  for (let i = 1; i < 7; i++) {
    h.setTick(i)
    h.trigger.update(1100 + i * 100)
  }
  assert.equal(h.shots.length, 1)
  h.setTick(7)
  h.trigger.update(1800)
  assert.equal(h.shots.length, 2)
  h.trigger.release()
  h.shots[1](true)
  h.setTick(14)
  h.trigger.update(2500)
  assert.equal(h.shots.length, 2)
})

test("Space does not fire when disconnected, destroyed or atlas is open", () => {
  const h = harness()
  h.setActive(false)
  h.trigger.press()
  assert.equal(h.shots.length, 0)
  h.setActive(true)
  assert.equal(h.trigger.update(1000), true)
  h.trigger.release()
  assert.equal(h.shots.length, 1)
})

test("server errors throttle retries, which can resume on valid next tick", () => {
  const h = harness()
  h.trigger.press()
  h.shots[0](false, "out_of_range")
  h.setTick(1)
  h.setTime(1200)
  assert.equal(h.trigger.update(1200), false)
  h.setTick(2)
  h.setTime(1351)
  assert.equal(h.trigger.update(1351), true)
  h.shots[1](false, "weapon_cooldown")
  h.setReady(5)
  h.setTick(5)
  h.setTime(1400)
  assert.equal(h.trigger.update(1400), false)
  h.setTime(1477)
  assert.equal(h.trigger.update(1477), true)
  assert.equal(h.shots.length, 3)
})
