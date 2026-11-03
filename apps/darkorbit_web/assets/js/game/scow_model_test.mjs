import assert from "node:assert/strict"
import test from "node:test"
import * as THREE from "three"
import {SCOW_SPEC, SCOW_MODEL_ID, isScowModelId, createScowModel} from "./scow_model.mjs"

test("Scow is a separate merchant class with grounded recognition-guide stats", () => {
  assert.equal(SCOW_MODEL_ID, "scow")
  assert.equal(SCOW_SPEC.role, "merchant")
  assert.equal(SCOW_SPEC.lengthMetres, 23)
  assert.equal(SCOW_SPEC.cargoTonnes, 10)
  assert.equal(SCOW_SPEC.armor, 210)
  assert.equal(SCOW_SPEC.garnetLaser, 10)
  assert.equal(SCOW_SPEC.hasMissiles, false)
})

test("real solar merchant NPC instances use the Scow mesh, never the Dart", () => {
  for (const id of ["scow", "solar-scow-1", "solar-scow-9735"]) {
    assert.equal(isScowModelId(id), true)
  }
  for (const id of ["dart", "solar-dart-1", "solar-scow-0",
                     "solar-scow-forged", "", null]) {
    assert.equal(isScowModelId(id), false)
  }
})

test("Scow procedural model has a cargo deck, blue hull, and targeting ring", () => {
  const scow = createScowModel(THREE)
  assert.equal(scow.userData.modelId, "scow")
  assert.equal(scow.name, "Scow light cargo trader")
  assert.ok(scow.children.length > 15)
  assert.ok(scow.userData.ring)
  assert.equal(scow.userData.ring.visible, false)
  assert.equal(scow.children.at(0).material.color.getHex(), 0x315f93)
  assert.ok(scow.children.some(child => child.geometry?.type === "SphereGeometry"))
  assert.ok(scow.children.some(child => child.geometry?.type === "BoxGeometry"))
})
