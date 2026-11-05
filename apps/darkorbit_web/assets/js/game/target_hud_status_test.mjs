import assert from "node:assert/strict"
import test from "node:test"
import {surrenderedTargetLabel} from "./target_hud_status.mjs"

test("surrendered NPC overrides the ordinary target label", () => {
  assert.equal(surrenderedTargetLabel({kind: "npc", state: "surrendered", displayName: "Scow Captain"}),
    "SURRENDERED · Scow Captain")
})

test("other states and player ships never show surrender", () => {
  for (const state of ["cruise", "evade", "attack", "destroyed", null]) {
    assert.equal(surrenderedTargetLabel({kind: "npc", state, displayName: "Scow"}), null)
  }
  assert.equal(surrenderedTargetLabel({kind: "player", state: "surrendered"}), null)
  assert.equal(surrenderedTargetLabel(null), null)
})

test("missing and long names remain safe for the stereo instrument", () => {
  assert.equal(surrenderedTargetLabel({kind: "npc", state: "surrendered"}),
    "SURRENDERED · CONTACT")
  assert.equal(surrenderedTargetLabel({kind: "npc", state: "surrendered", displayName: "Scow trader from Jupiter's freight guild"}),
    "SURRENDERED · Scow trader from Ju")
})
