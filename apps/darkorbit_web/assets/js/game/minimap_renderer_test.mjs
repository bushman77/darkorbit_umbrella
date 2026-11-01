import assert from "node:assert/strict"
import test from "node:test"

import {
  MINIMAP_FRAME_INTERVAL_MS,
  MinimapNavigation,
  MinimapRenderer,
  minimapProjection,
  minimapWorldPoint,
} from "./minimap_renderer.mjs"

class FakeGradient {
  addColorStop() {}
}

class FakeClassList {
  constructor() {
    this.values = new Set()
  }

  add(value) {
    this.values.add(value)
  }

  remove(value) {
    this.values.delete(value)
  }

  contains(value) {
    return this.values.has(value)
  }
}

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
      buttons: type === "pointerup" ? 0 : 1,
      clientX: 0,
      clientY: 0,
      pointerId: 1,
      pointerType: "mouse",
      defaultPrevented: false,
      preventDefault() {
        this.defaultPrevented = true
      },
      ...properties,
    }

    for (const listener of this.listeners.get(type) || []) listener(event)
    return event
  }

  listenerCount(type) {
    return (this.listeners.get(type) || []).length
  }
}

class FakeContext {
  constructor() {
    this.arcs = []
    this.lineTos = []
    this.strokeRects = []
    this.clears = 0
  }

  setTransform() {}
  clearRect() {
    this.clears += 1
  }
  fillRect() {}
  strokeRect(...values) {
    this.strokeRects.push(values)
  }
  createLinearGradient() {
    return new FakeGradient()
  }
  beginPath() {}
  moveTo() {}
  lineTo(...values) {
    this.lineTos.push(values)
  }
  arc(...values) {
    this.arcs.push(values)
  }
  fill() {}
  stroke() {}
  save() {}
  restore() {}
  setLineDash() {}
}

class FakeCanvas extends FakeEventTarget {
  constructor(width = 250, height = 150, left = 100, top = 50) {
    super()
    this.rect = {width, height, left, top}
    this.context = new FakeContext()
    this.classList = new FakeClassList()
    this.capturedPointers = new Set()
    this.width = 0
    this.height = 0
  }

  getContext() {
    return this.context
  }

  getBoundingClientRect() {
    return this.rect
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

const boundaries = {width: 20_000, height: 12_000}

test("minimap projection converts world and CSS coordinates consistently at center and boundaries", () => {
  const projection = minimapProjection(boundaries, {width: 250, height: 150})
  assert.ok(Math.abs(projection.x - 16.66666666666667) < 0.000_001)
  assert.ok(Math.abs(projection.width - 216.66666666666666) < 0.000_001)
  assert.equal(projection.y, 10)
  assert.equal(projection.height, 130)

  const center = {x: 10_000, y: 6_000}
  assert.deepEqual(projection.point(center), {x: 125, y: 75})
  assert.deepEqual(projection.worldPoint(projection.point(center)), center)
  assert.deepEqual(projection.worldPoint({x: projection.x, y: projection.y}), {x: 0, y: 0})
  assert.deepEqual(
    projection.worldPoint({x: projection.x + projection.width, y: projection.y + projection.height}),
    {x: boundaries.width, y: boundaries.height}
  )
})

test("letterboxed clicks are rejected while projected boundary clicks remain valid", () => {
  const canvas = new FakeCanvas(300, 300, 40, 70)
  const projection = minimapProjection(boundaries, canvas.rect)
  assert.equal(projection.x, 10)
  assert.equal(projection.y, 66)

  assert.equal(minimapWorldPoint({clientX: 190, clientY: 135}, canvas, boundaries), null)
  assert.deepEqual(
    minimapWorldPoint({clientX: 190, clientY: 136}, canvas, boundaries),
    {x: 10_000, y: 0}
  )
  assert.deepEqual(
    minimapWorldPoint({clientX: 330, clientY: 304}, canvas, boundaries),
    {x: boundaries.width, y: boundaries.height}
  )
})

test("CSS resize and device pixel ratio keep click projection independent from backing pixels", () => {
  const canvas = new FakeCanvas()
  const renderer = new MinimapRenderer({
    canvas,
    getEntities: () => [],
    getBoundaries: () => boundaries,
    getSelfId: () => null,
    getDevicePixelRatio: () => 2,
    resizeObserverFactory: () => null,
  }).start()

  assert.equal(canvas.width, 500)
  assert.equal(canvas.height, 300)
  assert.deepEqual(
    minimapWorldPoint({clientX: 225, clientY: 125}, canvas, boundaries),
    {x: 10_000, y: 6_000}
  )

  canvas.rect = {width: 400, height: 200, left: 20, top: 30}
  assert.equal(renderer.resize(), true)
  assert.equal(canvas.width, 800)
  assert.equal(canvas.height, 400)
  assert.deepEqual(
    minimapWorldPoint({clientX: 220, clientY: 130}, canvas, boundaries),
    {x: 10_000, y: 6_000}
  )
})

test("one renderer owns resize lifecycle, entity markers, destination feedback, and clearing", () => {
  const canvas = new FakeCanvas()
  let observed = 0
  let disconnected = 0
  let destination = {x: 20_000, y: 12_000}
  const entities = [
    {id: "pilot", kind: "player", status: "alive", render: {x: 10_000, y: 6_000}},
    {id: "wing", kind: "player", status: "alive", render: {x: 5_000, y: 3_000}},
    {id: "npc:one", kind: "npc", status: "alive", render: {x: 20_000, y: 12_000}},
    {id: "npc:gone", kind: "npc", status: "destroyed", render: {x: 0, y: 0}},
  ]
  const renderer = new MinimapRenderer({
    canvas,
    getEntities: () => entities,
    getBoundaries: () => boundaries,
    getSelfId: () => "pilot",
    getDestination: () => destination,
    getDevicePixelRatio: () => 2,
    resizeObserverFactory: () => ({
      observe() {
        observed += 1
      },
      disconnect() {
        disconnected += 1
      },
    }),
  })

  renderer.start().start()
  assert.equal(observed, 1)
  assert.equal(renderer.draw(0), true)
  assert.equal(renderer.draw(MINIMAP_FRAME_INTERVAL_MS - 1), false)
  assert.equal(canvas.context.arcs.length, 5)
  assert.ok(Math.abs(canvas.context.lineTos[0][0] - 233.33333333333331) < 1e-9)
  assert.equal(canvas.context.lineTos[0][1], 140)
  assert.ok(Math.abs(canvas.context.arcs[0][0] - 233.33333333333331) < 1e-9)
  assert.equal(canvas.context.arcs[0][1], 140)

  destination = null
  assert.equal(renderer.draw(MINIMAP_FRAME_INTERVAL_MS, true), true)
  assert.equal(canvas.context.arcs.length, 9)
  assert.equal(canvas.context.strokeRects.length, 2)

  canvas.rect = {width: 0, height: 0, left: 0, top: 0}
  assert.equal(renderer.draw(MINIMAP_FRAME_INTERVAL_MS * 2), false)

  renderer.stop()
  assert.equal(disconnected, 1)
  assert.equal(renderer.draw(100), false)
})

const navigationSetup = () => {
  const canvas = new FakeCanvas()
  const windowTarget = new FakeEventTarget()
  const documentTarget = new FakeEventTarget()
  const commands = []
  const state = {locked: true, visible: true, collapsed: false, connected: true}
  const combat = {selectedTargetId: "npc:one", engagedTargetId: "npc:one"}
  const navigation = new MinimapNavigation({
    canvas,
    windowTarget,
    documentTarget,
    getBoundaries: () => boundaries,
    canNavigate: () => state.locked && state.visible && !state.collapsed && state.connected,
    sendDestination: destination => {
      commands.push(destination)
      return true
    },
  }).attach()

  const click = (clientX, clientY, pointerId = 1, properties = {}) => {
    const down = canvas.dispatch("pointerdown", {clientX, clientY, pointerId, ...properties})
    const up = canvas.dispatch("pointerup", {clientX, clientY, pointerId, ...properties})
    return {down, up}
  }

  return {canvas, combat, commands, documentTarget, navigation, state, windowTarget, click}
}

test("locked minimap clicks replace destinations without mutating active combat state", () => {
  const context = navigationSetup()
  const combatBefore = {...context.combat}

  context.click(225, 125, 1)
  context.click(125, 70, 2)

  assert.equal(context.commands.length, 2)
  assert.deepEqual(context.commands[0], {x: 10_000, y: 6_000})
  assert.ok(Math.abs(context.commands[1].x - 10_000 / 13) < 1e-9)
  assert.ok(Math.abs(context.commands[1].y - 12_000 / 13) < 1e-9)
  assert.deepEqual(context.combat, combatBefore)
  assert.equal(context.canvas.hasPointerCapture(1), false)
})

test("editing, hidden, collapsed, disconnected, right-click, letterbox, and drag gestures suppress travel", () => {
  const context = navigationSetup()
  const suppressedStates = [
    {locked: false, visible: true, collapsed: false, connected: true},
    {locked: true, visible: false, collapsed: false, connected: true},
    {locked: true, visible: true, collapsed: true, connected: true},
    {locked: true, visible: true, collapsed: false, connected: false},
  ]

  for (const state of suppressedStates) {
    Object.assign(context.state, state)
    context.click(225, 125)
  }

  Object.assign(context.state, {locked: true, visible: true, collapsed: false, connected: true})
  context.click(225, 125, 5, {button: 2, buttons: 2})
  context.click(225, 55, 6)
  context.canvas.dispatch("pointerdown", {clientX: 225, clientY: 125, pointerId: 7})
  context.canvas.dispatch("pointermove", {clientX: 245, clientY: 125, pointerId: 7})
  context.canvas.dispatch("pointerup", {clientX: 245, clientY: 125, pointerId: 7})

  assert.deepEqual(context.commands, [])
  const menu = context.canvas.dispatch("contextmenu", {button: 2, buttons: 2})
  assert.equal(menu.defaultPrevented, true)
})

test("pointer cancellation and destroy release capture and remove every listener", () => {
  const context = navigationSetup()
  context.navigation.attach()
  assert.equal(context.canvas.listenerCount("pointerdown"), 1)

  context.canvas.dispatch("pointerdown", {clientX: 225, clientY: 125, pointerId: 9})
  assert.equal(context.canvas.hasPointerCapture(9), true)
  context.canvas.dispatch("pointercancel", {pointerId: 9})
  assert.equal(context.canvas.hasPointerCapture(9), false)
  assert.equal(context.commands.length, 0)

  context.canvas.dispatch("pointerdown", {clientX: 225, clientY: 125, pointerId: 10})
  context.navigation.destroy()
  assert.equal(context.canvas.hasPointerCapture(10), false)
  assert.equal(context.canvas.listenerCount("pointerdown"), 0)
  assert.equal(context.windowTarget.listenerCount("pointerup"), 0)
  context.click(225, 125, 11)
  assert.equal(context.commands.length, 0)
})

test("hidden or unavailable minimap canvases fail safely", () => {
  const canvas = new FakeCanvas(0, 0)
  const renderer = new MinimapRenderer({
    canvas,
    getEntities: () => [],
    getBoundaries: () => boundaries,
    getSelfId: () => null,
    resizeObserverFactory: () => null,
  }).start()

  assert.equal(renderer.draw(0), false)
  assert.equal(minimapProjection({width: 0, height: 12_000}, {width: 250, height: 150}), null)
  assert.equal(minimapProjection(boundaries, {width: 0, height: 150}), null)
  assert.equal(minimapWorldPoint({clientX: Number.NaN, clientY: 1}, canvas, boundaries), null)
})
