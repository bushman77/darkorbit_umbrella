import assert from "node:assert/strict"
import test from "node:test"
import {
  ORBITAL_MAP_PATTERN, validOrbitalMapId, shouldEnterOrbitalRegion,
} from "./orbital_regions.mjs"

test("all nine current SOL destinations, including Earth, are legal orbital map IDs", () => {
  assert.ok(ORBITAL_MAP_PATTERN instanceof RegExp)
  assert.equal(validOrbitalMapId("1-1"), true) // legacy test map
  for (const id of ["mercury", "venus", "earth", "mars", "jupiter",
                    "saturn", "uranus", "neptune", "pluto"]) {
    assert.equal(validOrbitalMapId("sol:" + id), true)
  }
})

test("client accepts future registered body IDs but never authorizes them", () => {
  for (const id of ["sol:ceres", "alpha_centauri:proxima-b", "new_system:world_42"]) {
    assert.equal(validOrbitalMapId(id), true)
    assert.equal(shouldEnterOrbitalRegion("sol:earth", id), true)
    // The Phoenix join still checks pilot's assigned map and rejects any
    // otherwise legal but unregistered / unauthorized ID.
  }
})

test("malformed map IDs and duplicate transitions are rejected", () => {
  for (const id of ["2-1", "sol:", "SOL:earth", "sol:../earth",
                    "sol:earth/foo", "sol:earth?x=1", "", null, 3, {}]) {
    assert.equal(validOrbitalMapId(id), false)
    assert.equal(shouldEnterOrbitalRegion("sol:earth", id), false)
  }
  assert.equal(shouldEnterOrbitalRegion("sol:earth", "sol:earth"), false)
  assert.equal(shouldEnterOrbitalRegion("1-1", "sol:venus"), true)
  assert.equal(shouldEnterOrbitalRegion("sol:venus", "sol:earth"), true)
  assert.equal(shouldEnterOrbitalRegion("sol:venus", "1-1"), true)
  assert.equal(shouldEnterOrbitalRegion("sol:earth", "sol:venus", true), false)
  assert.equal(validOrbitalMapId("sol:free_123"), true)
  assert.equal(shouldEnterOrbitalRegion("sol:earth", "sol:free_123"), true)
})
