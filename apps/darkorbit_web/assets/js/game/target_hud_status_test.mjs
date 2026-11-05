import assert from "node:assert/strict"
import test from "node:test"
import {surrenderedHudLabel, surrenderedTargetLabel} from "./target_hud_status.mjs"

const scow = (pilotId, state = "surrendered", displayName = "Hauler-2") => ({
  kind: "npc", npcTypeId: "solar-scow-" + pilotId, state, displayName,
})
const client = ({entities = [], selected = null, pilot = "3", tactical = false,
  helmet = false} = {}) => ({
  selfId: pilot,
  selectedTargetId: selected,
  entities: new Map(entities.map(entity => [entity.id, entity])),
  navComputer: {solarNavigation: helmet
    ? {tactical_active: tactical}
    : {tactical_encounter: tactical ? {id: "contact-1"} : null}},
})

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

test("desktop shows an owned surrender with no target lock", () => {
  const own = {id: "npc-one", ...scow(3)}
  assert.equal(surrenderedHudLabel(client({entities: [own], tactical: true})),
    "SURRENDERED · Hauler-2")
})

test("HMD shows an owned surrender with no target lock", () => {
  const own = {id: "npc-one", ...scow(3)}
  assert.equal(surrenderedHudLabel(client({entities: [own], tactical: true, helmet: true})),
    "SURRENDERED · Hauler-2")
})

test("other pilots' surrendered ships are not displayed", () => {
  const other = {id: "npc-other", ...scow(4)}
  assert.equal(surrenderedHudLabel(client({entities: [other], tactical: true})), null)
  assert.equal(surrenderedHudLabel(client({entities: [other], tactical: true, helmet: true})), null)
})

test("no tactical encounter or no surrender leaves the HUD alone", () => {
  const own = {id: "npc-one", ...scow(3)}
  assert.equal(surrenderedHudLabel(client({entities: [own]})), null)
  assert.equal(surrenderedHudLabel(client({entities: [own], helmet: true})), null)
  assert.equal(surrenderedHudLabel(client({entities: [{...own, state: "evade"}], tactical: true})), null)
  assert.equal(surrenderedHudLabel(null), null)
})

test("a directly selected surrendered target works without tactical metadata", () => {
  const selected = {id: "npc-one", ...scow(5)}
  assert.equal(surrenderedHudLabel(client({entities: [selected], selected: "npc-one"})),
    "SURRENDERED · Hauler-2")
})

test("future solar tactical ship classes can surrender without a lock", () => {
  const own = {id: "npc-dart", kind: "npc", npcTypeId: "solar-dart-3",
    state: "surrendered", displayName: "Sentinel-3"}
  assert.equal(surrenderedHudLabel(client({entities: [own], tactical: true})),
    "SURRENDERED · Sentinel-3")
  assert.equal(surrenderedHudLabel(client({entities: [own], tactical: true, helmet: true})),
    "SURRENDERED · Sentinel-3")
  assert.equal(surrenderedHudLabel(client({entities: [
    {...own, npcTypeId: "ambient-dart-3"}], tactical: true})), null)
})
