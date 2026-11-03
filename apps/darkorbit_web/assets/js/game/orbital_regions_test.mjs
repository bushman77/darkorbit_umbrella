import assert from "node:assert/strict"
import test from "node:test"
import {ORBITAL_MAP_IDS, validOrbitalMapId, shouldEnterOrbitalRegion} from "./orbital_regions.mjs"

test("all eight non-Earth planet maps are valid and distinct from the old Earth sector", () => {
  assert.equal(ORBITAL_MAP_IDS.length, 9)
  assert.equal(new Set(ORBITAL_MAP_IDS).size, 9)
  assert.equal(validOrbitalMapId("1-1"), true)
  for (const id of ["mercury", "venus", "mars", "jupiter", "saturn", "uranus", "neptune", "pluto"]) {
    assert.equal(validOrbitalMapId("sol:" + id), true)
  }
})

test("client refuses arbitrary map IDs and unnecessary or duplicate transitions", () => {
  for (const id of ["2-1", "sol:sun", "sol:fake", "", null, 3, {}]) {
    assert.equal(validOrbitalMapId(id), false)
    assert.equal(shouldEnterOrbitalRegion("1-1", id), false)
  }
  assert.equal(shouldEnterOrbitalRegion("1-1", "1-1"), false)
  assert.equal(shouldEnterOrbitalRegion("1-1", "sol:venus"), true)
  assert.equal(shouldEnterOrbitalRegion("sol:venus", "sol:earth"), false)
  assert.equal(shouldEnterOrbitalRegion("sol:venus", "1-1"), true)
  assert.equal(shouldEnterOrbitalRegion("1-1", "sol:venus", true), false)
})
