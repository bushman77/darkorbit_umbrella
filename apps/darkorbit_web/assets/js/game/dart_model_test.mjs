import assert from "node:assert/strict"
import test from "node:test"
import {
  DART_MODEL_ID, DART_HULL_POINTS, DART_HULL_FACES, dartHeadingRotation,
  isDartModelId,
} from "./dart_model.mjs"

test("Dart fighter uses an original swept delta-wing silhouette", () => {
  assert.equal(DART_MODEL_ID, "dart")
  assert.equal(DART_HULL_POINTS.length, 9)
  assert.equal(DART_HULL_FACES.length, 14)
  assert.ok(DART_HULL_POINTS[0][2] < -2)
  assert.ok(DART_HULL_POINTS[1][0] < -2)
  assert.ok(DART_HULL_POINTS[2][0] > 2)
  assert.equal(DART_HULL_POINTS[1][2], DART_HULL_POINTS[2][2])
  for (const face of DART_HULL_FACES) {
    assert.equal(face.length, 3)
    assert.ok(face.every(index => index >= 0 && index < DART_HULL_POINTS.length))
  }
})

test("Dart nose follows actual world-map heading without reversed steering", () => {
  assert.ok(Math.abs(dartHeadingRotation(-Math.PI / 2)) < 1e-9)
  assert.ok(Math.abs(dartHeadingRotation(0) + Math.PI / 2) < 1e-9)
  assert.ok(Math.abs(dartHeadingRotation(Math.PI / 2) + Math.PI) < 1e-9)
  assert.ok(Math.abs(dartHeadingRotation(Math.PI) + Math.PI * 1.5) < 1e-9)
})

test("live SOL tactical Dart variants retain the same real fighter model", () => {
  assert.equal(isDartModelId("dart"), true)
  assert.equal(isDartModelId("solar-dart-9731"), true)
  assert.equal(isDartModelId("solar-dart-1"), true)
  assert.equal(isDartModelId("solar-dart-0"), false)
  assert.equal(isDartModelId("solar-dart-foo"), false)
  assert.equal(isDartModelId("raider"), false)
  assert.equal(isDartModelId(null), false)
})
