import assert from "node:assert/strict"
import test from "node:test"
import {renderHelmetEncounter} from "./helmet_encounter_view.mjs"

const node = () => ({textContent: ""})
function fixture() {
  const titles = [node(), node()]
  const kinds = [node(), node()]
  const root = {
    hidden: true,
    querySelectorAll(selector) {
      return selector === "[data-helmet-encounter-title]" ? titles :
        selector === "[data-helmet-encounter-kind]" ? kinds : []
    },
  }
  return {root, titles, kinds}
}

test("an authenticated headset alert appears in both stereo eyes", () => {
  const {root, titles, kinds} = fixture()
  renderHelmetEncounter(root, {
    paused: true,
    encounter: {
      id: "flyby:traffic:sol:vesper-02:1",
      call_sign: "Vesper-02",
      classification: "neutral_flyby",
    },
  })
  assert.equal(root.hidden, false)
  assert.deepEqual(titles.map(x => x.textContent), ["Vesper-02", "Vesper-02"])
  assert.deepEqual(kinds.map(x => x.textContent),
    ["NEUTRAL CONTACT · CRUISE PAUSED", "NEUTRAL CONTACT · CRUISE PAUSED"])
})

test("hostile classification is clearly visible; resuming hides both panels", () => {
  const {root, kinds} = fixture()
  renderHelmetEncounter(root, {
    paused: true,
    encounter: {id: "one", call_sign: "Sentinel-07", classification: "hostile_contact"},
  })
  assert.equal(kinds[1].textContent, "HOSTILE CONTACT · CRUISE PAUSED")
  renderHelmetEncounter(root, {paused: false, encounter: null})
  assert.equal(root.hidden, true)
  renderHelmetEncounter(root, null)
  assert.equal(root.hidden, true)
})

test("missing or invalid pending contacts are not shown", () => {
  const {root} = fixture()
  renderHelmetEncounter(root, {paused: true, encounter: {call_sign: "Missing ID"}})
  assert.equal(root.hidden, true)
  renderHelmetEncounter(null, {paused: true, encounter: {id: "one"}})
})
