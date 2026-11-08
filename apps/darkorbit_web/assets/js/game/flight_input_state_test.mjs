import test from "node:test"
import assert from "node:assert/strict"
import {flightInputState as state, FLIGHT_INPUT_LABELS} from "./flight_input_state.mjs"

const ready = {sectorJoined: true, ship: {status: "active"}}

test("joined manual cockpit admits keyboard and mouse input", () => {
  assert.equal(state(ready), "ready")
  assert.equal(state({...ready, ship: {status: "idle"}}), "ready")
})

test("blocked flight input reports a specific truthful reason", () => {
  assert.equal(state({...ready, atlasOpen: true}), "atlas")
  assert.equal(state({...ready, docked: true}), "docked")
  assert.equal(state({...ready, encounterHeld: true, cruiseLocked: true}), "encounter")
  assert.equal(state({...ready, cruiseLocked: true}), "cruise")
  assert.equal(state({...ready, sectorJoined: false}), "disconnected")
  assert.equal(state({...ready, ship: null}), "synchronizing")
  assert.equal(state({...ready, ship: {status: "destroyed"}}), "destroyed")
  for (const reason of ["docked", "encounter", "cruise", "disconnected", "synchronizing", "destroyed"]) {
    assert.ok(FLIGHT_INPUT_LABELS[reason].length > 10)
  }
})

test("viewing autopilot in cockpit doesn't silently disengage cruise", () => {
  const situation = {...ready, cruiseLocked: true, atlasOpen: false}
  assert.equal(state(situation), "cruise")
  assert.equal(situation.cruiseLocked, true)
})
