import assert from "node:assert/strict"
import test from "node:test"
import * as THREE from "three"
import {EncounterShipVisual} from "./encounter_ship.js"

const voyage = shipClass => ({
  status: "traveling",
  origin_position_km: {x: 0, y: 0, z: 0},
  destination_position_km: {x: 1000000, y: 0, z: 0},
  encounter: {
    id: "flyby:traffic:sol:cruise-1:1",
    call_sign: "Harbor-1",
    ship_class: shipClass,
    mode: "strategic_flyby",
    distance_km: 100000,
    relative_position_km: {x: 100000, y: 0, z: 0},
  },
})

test("a visible Harbor close pass uses actual blue Scow geometry, not gray generic placeholder", () => {
  const scene = new THREE.Scene()
  const camera = new THREE.PerspectiveCamera()
  const view = new EncounterShipVisual(THREE, scene)
  view.update(voyage("scow"), camera)
  assert.equal(view.shipClass, "scow")
  assert.equal(view.group.userData.modelId, "scow")
  assert.equal(view.group.name, "Scow light cargo trader")
  assert.equal(view.group.children.at(0).material.color.getHex(), 0x315f93)
  assert.ok(view.group.visible)
  assert.equal(scene.children.includes(view.group), true)
  view.dispose()
  assert.equal(view.group, null)
})

test("changing encounter class replaces model without leaving a stale fighter or cargo hull", () => {
  const scene = new THREE.Scene()
  const camera = new THREE.PerspectiveCamera()
  const view = new EncounterShipVisual(THREE, scene)
  const scow = voyage("scow")
  view.update(scow, camera)
  const oldGroup = view.group
  view.update(voyage("dart"), camera)
  assert.notEqual(view.group, oldGroup)
  assert.equal(view.group.userData.modelId, "dart")
  assert.equal(scene.children.includes(oldGroup), false)
  assert.equal(scene.children.includes(view.group), true)
  assert.equal(scene.children.length, 1)

  view.update(null, camera)
  assert.equal(view.group.visible, false)
  view.dispose()
})

test("encounter hold keeps the pending Scow contact visible when passive sensor range has expired", () => {
  const view = new EncounterShipVisual(THREE, new THREE.Scene())
  const navigation = voyage("scow")
  const held = {...navigation, encounter: null,
    pending_encounter: navigation.encounter, cruise_paused: true}
  const result = view.update(held, new THREE.PerspectiveCamera())
  assert.equal(result.shipClass, "scow")
  assert.equal(view.group.userData.modelId, "scow")
  view.dispose()
})
