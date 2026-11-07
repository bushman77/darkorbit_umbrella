import assert from "node:assert/strict"
import test from "node:test"
import {tacticalEncounterAction} from "./solar_encounter_actions.mjs"

test("a peaceful trader offers an explicit Attack vessel choice", () => {
  assert.deepEqual(tacticalEncounterAction("neutral_flyby"),
    {visible: true, label: "Attack vessel"})
})

test("hostile raiders and hostile patrol attention can be intercepted", () => {
  for (const classification of ["hostile_contact", "patrol_attention"]) {
    assert.deepEqual(tacticalEncounterAction(classification),
      {visible: true, label: "Engage / Enter combat"})
  }
})

test("unknown and client-invented classifications cannot show a combat option", () => {
  for (const classification of ["peaceful", "friendly", null, undefined, ""]) {
    assert.equal(tacticalEncounterAction(classification).visible, false)
  }
})
