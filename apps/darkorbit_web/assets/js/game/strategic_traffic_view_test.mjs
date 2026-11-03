import assert from "node:assert/strict"
import test from "node:test"
import {NavigationComputer} from "./navigation_computer.mjs"

const node = () => ({
  children: [],
  textContent: "",
  className: "",
  dataset: {},
  append(...items) { this.children.push(...items) },
  appendChild(item) { this.children.push(item) },
  replaceChildren() { this.children = [] },
})

function setup({connected = true, hail = null} = {}) {
  const contacts = node()
  const comms = node()
  const root = {
    querySelector(selector) {
      return {
        "#nav-traffic-contacts": contacts,
        "#nav-traffic-comms": comms,
      }[selector] || null
    },
  }
  const nav = new NavigationComputer({
    root,
    getEntities: () => new Map(),
    getSelfId: () => 1,
    getBoundaries: () => ({}),
    isConnected: () => connected,
    engage: () => {},
    halt: () => {},
    solarHail: hail || ((_id, done) => done(false, null, "unavailable")),
  })
  return {nav, contacts, comms}
}

test("Atlas shows an in-range neutral freighter and uses safe text-only rendering", () => {
  const previousDocument = globalThis.document
  globalThis.document = {createElement: () => node()}
  try {
    const {nav, contacts} = setup()
    nav.solarNavigation = {
      contacts: [{
        id: "traffic:sol:meridian-01",
        call_sign: "Meridian-01",
        disposition: "neutral",
        origin_id: "earth",
        destination_id: "mars",
        state: "in_transit",
        distance_km: 1_234_567.8,
      }],
    }
    nav.renderTrafficContacts()
    assert.equal(contacts.children.length, 1)
    const card = contacts.children[0]
    assert.equal(card.children[0].textContent, "Meridian-01 · NEUTRAL")
    assert.match(card.children[1].textContent, /earth → mars/)
    assert.match(card.children[1].textContent, /1,234,568 game km/)
    assert.equal(card.children[2].dataset.trafficHail, "traffic:sol:meridian-01")
    assert.equal(card.children[2].textContent, "Hail freighter")

    nav.solarNavigation = {...nav.solarNavigation, contacts: []}
    nav.renderTrafficContacts()
    assert.equal(contacts.children.length, 0)
    assert.equal(contacts.textContent, "No vessels currently in sensor range.")
  } finally {
    globalThis.document = previousDocument
  }
})

test("hails reveal cargo only from an authenticated response", () => {
  let callCount = 0
  const {nav, comms} = setup({
    hail: (id, done) => {
      assert.equal(id, "traffic:sol:meridian-01")
      callCount++
      done(true, {
        call_sign: "Meridian-01",
        message: "Independent cargo service. No assistance requested.",
        cargo: {industrial_machinery: 120},
      })
    },
  })
  nav.hailTraffic("traffic:sol:meridian-01")
  assert.equal(callCount, 1)
  assert.match(comms.textContent, /Meridian-01/)
  assert.match(comms.textContent, /industrial machinery: 120/)
  assert.equal(nav.draft.length, 0)
})

test("unavailable hails are shown as failures without changing an NPC's route", () => {
  const {nav, comms} = setup({
    hail: (_id, done) => done(false, null, "contact_out_of_range"),
  })
  nav.hailTraffic("traffic:sol:meridian-01")
  assert.match(comms.textContent, /contact_out_of_range/)
  const disconnected = setup({connected: false})
  disconnected.nav.hailTraffic("traffic:sol:meridian-01")
  assert.equal(disconnected.comms.textContent, "")
})
