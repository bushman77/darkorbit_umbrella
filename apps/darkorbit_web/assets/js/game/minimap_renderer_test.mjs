import assert from "node:assert/strict"
import test from "node:test"

import {MINIMAP_FRAME_INTERVAL_MS, MinimapRenderer, minimapProjection} from "./minimap_renderer.mjs"

class FakeGradient {
  addColorStop() {}
}

class FakeContext {
  constructor() {
    this.arcs = []
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
  arc(...values) {
    this.arcs.push(values)
  }
  fill() {}
}

class FakeCanvas {
  constructor(width = 250, height = 150) {
    this.rect = {width, height}
    this.context = new FakeContext()
    this.width = 0
    this.height = 0
  }

  getContext() {
    return this.context
  }

  getBoundingClientRect() {
    return this.rect
  }
}

test("minimap projection preserves map boundaries and accurate entity coordinates", () => {
  const projection = minimapProjection({width: 20_000, height: 12_000}, {width: 250, height: 150})
  assert.ok(Math.abs(projection.x - 16.66666666666667) < 0.000_001)
  assert.ok(Math.abs(projection.width - 216.66666666666666) < 0.000_001)
  assert.equal(projection.y, 10)
  assert.equal(projection.height, 130)
  assert.deepEqual(projection.point({x: 10_000, y: 6_000}), {x: 125, y: 75})
})

test("one minimap renderer owns resize lifecycle and throttled world rendering", () => {
  const canvas = new FakeCanvas()
  let observed = 0
  let disconnected = 0
  const entities = [
    {id: "pilot", kind: "player", status: "alive", render: {x: 10_000, y: 6_000}},
    {id: "npc:one", kind: "npc", status: "alive", render: {x: 20_000, y: 12_000}},
    {id: "npc:gone", kind: "npc", status: "destroyed", render: {x: 0, y: 0}},
  ]
  const renderer = new MinimapRenderer({
    canvas,
    getEntities: () => entities,
    getBoundaries: () => ({width: 20_000, height: 12_000}),
    getSelfId: () => "pilot",
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
  assert.equal(canvas.width, 500)
  assert.equal(canvas.height, 300)
  assert.equal(renderer.draw(0), true)
  assert.equal(renderer.draw(MINIMAP_FRAME_INTERVAL_MS - 1), false)
  assert.equal(renderer.draw(MINIMAP_FRAME_INTERVAL_MS), true)
  assert.equal(canvas.context.arcs.length, 4)
  assert.equal(canvas.context.strokeRects.length, 2)
  assert.equal(canvas.context.arcs[0][2], 3)
  assert.equal(canvas.context.arcs[1][2], 2.25)

  canvas.rect = {width: 0, height: 0}
  assert.equal(renderer.draw(MINIMAP_FRAME_INTERVAL_MS * 2), false)

  renderer.stop()
  assert.equal(disconnected, 1)
  assert.equal(renderer.draw(100), false)
})

test("hidden or unavailable minimap canvases fail safely", () => {
  const canvas = new FakeCanvas(0, 0)
  const renderer = new MinimapRenderer({
    canvas,
    getEntities: () => [],
    getBoundaries: () => ({width: 20_000, height: 12_000}),
    getSelfId: () => null,
    resizeObserverFactory: () => null,
  }).start()

  assert.equal(renderer.draw(0), false)
  assert.equal(minimapProjection({width: 0, height: 12_000}, {width: 250, height: 150}), null)
})
