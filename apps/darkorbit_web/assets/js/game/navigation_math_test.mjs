import assert from "node:assert/strict"
import test from "node:test"
import {
  NAV_CHART_SIZE, MAX_WAYPOINTS, chartProjection, chartWorldPoint,
  validWaypoint, appendWaypoint, routeDistance, parseCoordinates,
} from "./navigation_math.mjs"

const bounds = {width: 20_000, height: 12_000}

test("full navigation chart projects all map corners and roundtrips a point", () => {
  const projection = chartProjection(bounds)
  assert.deepEqual(chartWorldPoint(projection.point({x: 0, y: 0}), bounds), {x: 0, y: 0})
  const end = chartWorldPoint(projection.point({x: bounds.width, y: bounds.height}), bounds)
  assert.ok(end)
  assert.ok(Math.abs(end.x - bounds.width) < 1e-6)
  assert.ok(Math.abs(end.y - bounds.height) < 1e-6)
  const sample = {x: 3250, y: 8500}
  const result = chartWorldPoint(projection.point(sample), bounds)
  assert.ok(Math.abs(result.x - sample.x) < 1e-6)
  assert.ok(Math.abs(result.y - sample.y) < 1e-6)
  assert.equal(chartWorldPoint({x: 0, y: 0}, bounds), null)
  assert.ok(NAV_CHART_SIZE.width > NAV_CHART_SIZE.height)
})

test("waypoint selection clamps to domain validation rather than moving the ship", () => {
  assert.deepEqual(validWaypoint({x: 0, y: 12_000}, bounds), {x: 0, y: 12_000})
  assert.equal(validWaypoint({x: 20_001, y: 100}, bounds), null)
  assert.equal(validWaypoint({x: NaN, y: 50}, bounds), null)
  assert.equal(parseCoordinates("", 0, bounds), null)
  assert.equal(parseCoordinates("Infinity", 0, bounds), null)
  assert.deepEqual(parseCoordinates("1000", "1200", bounds), {x: 1000, y: 1200})
})

test("routes cap at eight waypoints and avoid duplicate consecutive points", () => {
  assert.equal(MAX_WAYPOINTS, 8)
  let draft = []
  for (let index = 0; index < MAX_WAYPOINTS; index++) {
    draft = appendWaypoint(draft, {x: index * 100, y: 300}, bounds)
  }
  assert.equal(draft.length, MAX_WAYPOINTS)
  assert.equal(appendWaypoint(draft, {x: 1000, y: 300}, bounds), draft)
  const first = [{x: 50, y: 50}]
  assert.equal(appendWaypoint(first, {x: 50.1, y: 50.1}, bounds), first)
})

test("preview distance accumulates each leg deterministically", () => {
  assert.equal(routeDistance({x: 0, y: 0}, [{x: 3, y: 4}, {x: 3, y: 8}]), 9)
  assert.equal(routeDistance(null, [{x: 1, y: 1}]), 0)
})
