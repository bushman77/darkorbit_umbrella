import assert from "node:assert/strict"
import test from "node:test"

import {PointerNavigation} from "./pointer_navigation.mjs"

class FakeEventTarget {
  constructor() {
    this.listeners = new Map()
  }

  addEventListener(type, listener) {
    const listeners = this.listeners.get(type) || []
    listeners.push(listener)
    this.listeners.set(type, listeners)
  }

  removeEventListener(type, listener) {
    const listeners = this.listeners.get(type) || []
    this.listeners.set(type, listeners.filter(candidate => candidate !== listener))
  }

  dispatch(type, properties = {}) {
    const event = {
      button: 0,
      buttons: 1,
      clientX: 0,
      clientY: 0,
      pointerId: 1,
      defaultPrevented: false,
      preventDefault() {
        this.defaultPrevented = true
      },
      ...properties,
    }

    for (const listener of this.listeners.get(type) || []) listener(event)
    return event
  }
}

class FakeCanvas extends FakeEventTarget {
  constructor() {
    super()
    this.capturedPointers = new Set()
  }

  setPointerCapture(pointerId) {
    this.capturedPointers.add(pointerId)
  }

  hasPointerCapture(pointerId) {
    return this.capturedPointers.has(pointerId)
  }

  releasePointerCapture(pointerId) {
    this.capturedPointers.delete(pointerId)
  }
}

class FakeScheduler {
  constructor() {
    this.time = 0
    this.nextId = 1
    this.tasks = new Map()
  }

  setTimer(callback, delay) {
    const id = this.nextId++
    this.tasks.set(id, {callback, dueAt: this.time + delay})
    return id
  }

  clearTimer(id) {
    this.tasks.delete(id)
  }

  advance(milliseconds) {
    const target = this.time + milliseconds

    while (true) {
      const next = [...this.tasks.entries()]
        .filter(([, task]) => task.dueAt <= target)
        .sort((left, right) => left[1].dueAt - right[1].dueAt)[0]

      if (!next) break

      const [id, task] = next
      this.tasks.delete(id)
      this.time = task.dueAt
      task.callback()
    }

    this.time = target
  }
}

const setup = ({ship = {x: 0, y: 0}, interceptPointerDown = () => false} = {}) => {
  const canvas = new FakeCanvas()
  const windowTarget = new FakeEventTarget()
  const documentTarget = new FakeEventTarget()
  const scheduler = new FakeScheduler()
  const camera = {x: 0, y: 0}
  const commands = []
  let shipPosition = ship

  const navigation = new PointerNavigation({
    canvas,
    windowTarget,
    documentTarget,
    now: () => scheduler.time,
    setTimer: (callback, delay) => scheduler.setTimer(callback, delay),
    clearTimer: id => scheduler.clearTimer(id),
    destinationForPointer: pointer => ({
      x: pointer.clientX + camera.x,
      y: pointer.clientY + camera.y,
    }),
    shipPosition: () => shipPosition,
    sendDestination: destination => commands.push(destination),
    interceptPointerDown,
  }).attach()

  return {
    camera,
    canvas,
    commands,
    documentTarget,
    navigation,
    scheduler,
    setShipPosition: position => shipPosition = position,
    windowTarget,
  }
}

test("a single left click sets a destination and release does not stop the ship", () => {
  const {canvas, commands, scheduler} = setup()

  const down = canvas.dispatch("pointerdown", {clientX: 120, clientY: 80, pointerId: 7})
  assert.equal(down.defaultPrevented, true)
  assert.equal(canvas.hasPointerCapture(7), true)
  assert.deepEqual(commands, [{x: 120, y: 80}])

  canvas.dispatch("pointerup", {buttons: 0, clientX: 120, clientY: 80, pointerId: 7})
  scheduler.advance(500)

  assert.equal(canvas.hasPointerCapture(7), false)
  assert.deepEqual(commands, [{x: 120, y: 80}])
})

test("an intercepted NPC press selects without issuing click or hold navigation", () => {
  const targeted = []
  const context = setup({
    interceptPointerDown: pointer => {
      const hit = pointer.clientX >= 90 && pointer.clientX <= 150
      if (hit) targeted.push(pointer)
      return hit
    },
  })

  const down = context.canvas.dispatch("pointerdown", {
    clientX: 120,
    clientY: 80,
    pointerId: 7,
  })
  context.scheduler.advance(400)
  context.canvas.dispatch("pointermove", {
    clientX: 300,
    clientY: 200,
    pointerId: 7,
  })
  context.canvas.dispatch("pointerup", {buttons: 0, pointerId: 7})

  assert.equal(down.defaultPrevented, true)
  assert.deepEqual(targeted, [{clientX: 120, clientY: 80}])
  assert.deepEqual(context.commands, [])
  assert.equal(context.canvas.hasPointerCapture(7), false)

  context.canvas.dispatch("pointerdown", {clientX: 300, clientY: 200, pointerId: 8})
  context.scheduler.advance(100)
  assert.deepEqual(context.commands, [{x: 300, y: 200}])
})

test("holding retargets at most every 100ms and follows pointer and camera changes", () => {
  const {camera, canvas, commands, scheduler} = setup()

  canvas.dispatch("pointerdown", {clientX: 100, clientY: 100})
  scheduler.advance(20)
  canvas.dispatch("pointermove", {clientX: 180, clientY: 120})
  assert.equal(commands.length, 1)

  scheduler.advance(80)
  assert.deepEqual(commands.at(-1), {x: 180, y: 120})

  camera.x = 15
  camera.y = 5
  scheduler.advance(100)
  assert.deepEqual(commands.at(-1), {x: 195, y: 125})
  assert.equal(commands.length, 3)
})

test("stationary input does not repeat an unchanged destination", () => {
  const {canvas, commands, scheduler} = setup()

  canvas.dispatch("pointerdown", {clientX: 200, clientY: 100})
  scheduler.advance(1_000)

  assert.deepEqual(commands, [{x: 200, y: 100}])
})

test("the ship dead zone suppresses continuous jitter without swallowing a click", () => {
  const {canvas, commands, scheduler, setShipPosition} = setup({ship: {x: 100, y: 100}})

  canvas.dispatch("pointerdown", {clientX: 105, clientY: 103})
  assert.deepEqual(commands, [{x: 105, y: 103}])

  scheduler.advance(100)
  canvas.dispatch("pointermove", {clientX: 108, clientY: 104})
  assert.equal(commands.length, 1)

  scheduler.advance(100)
  canvas.dispatch("pointermove", {clientX: 180, clientY: 100})
  assert.deepEqual(commands.at(-1), {x: 180, y: 100})

  setShipPosition({x: 180, y: 100})
  scheduler.advance(100)
  canvas.dispatch("pointermove", {clientX: 184, clientY: 102})
  scheduler.advance(200)
  assert.equal(commands.length, 2)
})

test("a throttled follow-up click is still delivered after release", () => {
  const {canvas, commands, scheduler} = setup()

  canvas.dispatch("pointerdown", {clientX: 100, clientY: 100, pointerId: 1})
  canvas.dispatch("pointerup", {buttons: 0, pointerId: 1})
  scheduler.advance(20)
  canvas.dispatch("pointerdown", {clientX: 220, clientY: 100, pointerId: 2})
  canvas.dispatch("pointerup", {buttons: 0, pointerId: 2})

  scheduler.advance(79)
  assert.equal(commands.length, 1)
  scheduler.advance(1)
  assert.deepEqual(commands, [{x: 100, y: 100}, {x: 220, y: 100}])
})

test("release preserves the final queued direction without continuing to retarget", () => {
  const {camera, canvas, commands, scheduler} = setup()

  canvas.dispatch("pointerdown", {clientX: 100, clientY: 100, pointerId: 1})
  scheduler.advance(20)
  canvas.dispatch("pointermove", {clientX: 220, clientY: 100, pointerId: 1})
  canvas.dispatch("pointerup", {buttons: 0, clientX: 220, clientY: 100, pointerId: 1})

  scheduler.advance(80)
  assert.deepEqual(commands, [{x: 100, y: 100}, {x: 220, y: 100}])

  camera.x = 100
  scheduler.advance(500)
  assert.equal(commands.length, 2)
})

test("cancellation paths stop retargeting and release pointer capture", async t => {
  const cases = [
    ["pointercancel", ({canvas}) => canvas.dispatch("pointercancel", {pointerId: 1})],
    ["lost pointer capture", ({canvas}) => canvas.dispatch("lostpointercapture", {pointerId: 1})],
    ["window blur", ({windowTarget}) => windowTarget.dispatch("blur")],
    ["hidden document", ({documentTarget}) => {
      documentTarget.hidden = true
      documentTarget.dispatch("visibilitychange")
    }],
    ["missing primary button", ({canvas}) => canvas.dispatch("pointermove", {buttons: 0, pointerId: 1})],
  ]

  for (const [name, cancel] of cases) {
    await t.test(name, () => {
      const context = setup()
      context.canvas.dispatch("pointerdown", {clientX: 100, clientY: 100, pointerId: 1})
      cancel(context)
      context.camera.x = 100
      context.scheduler.advance(500)

      assert.equal(context.commands.length, 1)
      assert.equal(context.canvas.hasPointerCapture(1), false)
    })
  }
})

test("non-left and secondary pointers are ignored", () => {
  const {canvas, commands} = setup()

  canvas.dispatch("pointerdown", {button: 2, buttons: 2, pointerId: 1})
  canvas.dispatch("pointerdown", {clientX: 100, pointerId: 2})
  canvas.dispatch("pointerdown", {clientX: 200, pointerId: 3})

  assert.deepEqual(commands, [{x: 100, y: 0}])
  assert.equal(canvas.hasPointerCapture(3), false)
})
