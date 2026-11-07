import assert from "node:assert/strict"
import test from "node:test"
import {renderHelmetSurrender, helmetSurrenderFromEntities} from "./helmet_surrender_view.mjs"

function fixture() {
  const eyes = [{textContent: ""}, {textContent: ""}]
  return {
    eyes,
    node: {
      hidden: true,
      querySelectorAll(selector) {
        return selector === "[data-helmet-surrender-name]" ? eyes : []
      },
    },
  }
}

test("phone's two SBS eyes show the surrender independently of desktop HUD", () => {
  const {node, eyes} = fixture()
  renderHelmetSurrender(node, {surrendered: true, call_sign: "Hauler-2"})
  assert.equal(node.hidden, false)
  assert.deepEqual(eyes.map(eye => eye.textContent), ["Hauler-2", "Hauler-2"])
  renderHelmetSurrender(node, {surrendered: false})
  assert.equal(node.hidden, true)
  renderHelmetSurrender(node, null)
  assert.equal(node.hidden, true)
})

test("snapshot fallback finds only the paired pilot's surrendered tactical ship", () => {
  const entities = new Map([
    ["enemy-4", {kind: "npc", state: "surrendered", npcTypeId: "solar-scow-4", displayName: "Other"}],
    ["scow", {kind: "npc", state: "surrendered", npcTypeId: "solar-scow-3", displayName: "Hauler-2"}],
  ])
  assert.deepEqual(helmetSurrenderFromEntities(entities, "3"),
    {surrendered: true, call_sign: "Hauler-2"})
  assert.deepEqual(helmetSurrenderFromEntities(entities, "7"), {surrendered: false})
})

test("snapshot removal or changed NPC state clears surrender", () => {
  assert.deepEqual(helmetSurrenderFromEntities(new Map(), "3"), {surrendered: false})
  assert.deepEqual(helmetSurrenderFromEntities(new Map([["scow", {
    kind: "npc", state: "evade", npcTypeId: "solar-scow-3",
  }]]), "3"), {surrendered: false})
  assert.deepEqual(helmetSurrenderFromEntities(null, null), {surrendered: false})
})

test("missing root, suspicious names and inactive statuses are safe", () => {
  renderHelmetSurrender(null, {surrendered: true, call_sign: "Hauler-2"})
  const {node, eyes} = fixture()
  renderHelmetSurrender(node, {surrendered: true, call_sign: "<test>"})
  assert.equal(eyes[0].textContent, "<test>")
  assert.equal(helmetSurrenderFromEntities(new Map([["scow", {
    kind: "npc", state: "surrendered", npcTypeId: "solar-scow-3",
    status: "destroyed",
  }]]), "3").surrendered, false)
})
