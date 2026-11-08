import test from "node:test"
import assert from "node:assert/strict"
import {dockingHoldFromEvent, syncDockingHold, dockingSeconds} from
  "./starbase_docking_countdown.mjs"

const hold = {entity_id: 17, station_id: "sol:starbase:green",
  started_tick: 42, remaining_ms: 5000, duration_ms: 5000}

test("five-second hold counts down locally without network traffic", () => {
  const start = dockingHoldFromEvent(hold, 1000)
  assert.equal(dockingSeconds(start, 1000), 5)
  assert.equal(dockingSeconds(start, 2101), 4)
  assert.equal(dockingSeconds(start, 5000), 1)
  assert.equal(dockingSeconds(start, 6000), 0)
  assert.equal(dockingSeconds(null, 6000), null)
})

test("frequent world snapshots never reset the active hold", () => {
  const start = dockingHoldFromEvent(hold, 1000)
  const same = syncDockingHold(start,
    {tick: 67, tick_ms: 100, docking_holds: [hold]}, 17, 3500)
  assert.equal(same, start)
  assert.equal(dockingSeconds(same, 3500), 3)
  assert.equal(syncDockingHold(same, {docking_holds: []}, 17, 3600), null)
  assert.equal(syncDockingHold(same, {docking_holds: [hold]}, 18, 3600), null)
})

test("late joins resume remaining time; malformed payloads are rejected", () => {
  const resumed = syncDockingHold(null,
    {tick: 80, tick_ms: 100, docking_holds: [hold]}, "17", 9000)
  assert.equal(dockingSeconds(resumed, 9000), 2)
  assert.equal(dockingSeconds(resumed, 9600), 1)
  assert.equal(dockingHoldFromEvent({...hold, started_tick: "42"}, 1000), null)
  assert.equal(dockingHoldFromEvent({...hold, remaining_ms: 99999}, 1000), null)
  assert.equal(dockingHoldFromEvent({...hold, remaining_ms: -5}, 1000), null)
})
