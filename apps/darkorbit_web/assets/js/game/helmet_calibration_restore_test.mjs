import test from "node:test"
import assert from "node:assert/strict"
import {restoredHelmetCalibration as restore} from "./helmet_calibration_restore.mjs"

test("existing PostgreSQL calibration overrides old browser cache", () => {
  assert.deepEqual(restore({
    server: {eyeGapPx: -72, eyeSepMm: 61},
    local: {eyeGapPx: 8, eyeSepMm: 64},
  }), {calibration: {eyeGapPx: -72, eyeSepMm: 61}, needsSave: false})
})

test("unsynced phone edit wins and is written on reconnect", () => {
  assert.deepEqual(restore({
    server: {eyeGapPx: -72, eyeSepMm: 61},
    local: {eyeGapPx: -76, eyeSepMm: 62}, dirty: true,
  }), {calibration: {eyeGapPx: -76, eyeSepMm: 62}, needsSave: true})
})

test("migrate previously calibrated phone into empty device row", () => {
  assert.deepEqual(restore({
    server: null,
    local: {eyeGapPx: -100, eyeSepMm: 59},
  }), {calibration: {eyeGapPx: -100, eyeSepMm: 59}, needsSave: true})
})

test("invalid database payload never becomes a display setting", () => {
  assert.deepEqual(restore({
    server: {eyeGapPx: -999, eyeSepMm: 64},
    local: {eyeGapPx: -22, eyeSepMm: 65},
  }), {calibration: {eyeGapPx: -22, eyeSepMm: 65}, needsSave: true})
})
