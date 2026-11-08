import test from "node:test"
import assert from "node:assert/strict"
import {ownStationWarning, stationWarningView} from "./station_warning.mjs"

test("station warning stays separate from planetary warnings", () => {
  const data = {
    planetary_warnings: [{entity_id: 5, level: "critical", planet_id: "earth"}],
    station_warnings: [{entity_id: 5, level: "caution",
      station_id: "sol:base:earth", clearance_km: 1600}],
  }
  const own = ownStationWarning(data, 5)
  assert.equal(own.station_id, "sol:base:earth")
  assert.equal(ownStationWarning(data, 9), null)
  assert.equal(ownStationWarning({planetary_warnings: data.planetary_warnings}, 5), null)
})

test("only authoritative station warnings render; no planetary impact text", () => {
  const view = stationWarningView({
    station_id: "sol:base:mars", level: "critical", clearance_km: 42.5,
  })
  assert.match(view.label, /REFINERY/)
  assert.match(view.detail, /43 KM TO STATION HULL/)
  assert.match(view.detail, /NO DOCKING CLEARANCE/)
  assert.doesNotMatch(view.detail, /PLANETARY|TO IMPACT/)
  for (const bad of [null, {}, {level: "caution", clearance_km: -2,
      station_id: "sol:base:earth"}, {level: "caution", clearance_km: 15,
      station_id: "non-station"}, {level: "clear", clearance_km: 0,
      station_id: "sol:base:earth"}]) {
    assert.equal(stationWarningView(bad), null)
  }
})

test("Green Starbase warning reflects the open approach and no docking permission", () => {
  const base = {entity_id: 19, station_id: "sol:starbase:green",
    distance_km: 480, clearance_km: 0}
  const own = ownStationWarning({station_warnings: [
    {...base, level: "approach"}]}, 19)
  assert.equal(own.level, "approach")
  const view = stationWarningView(own)
  assert.match(view.label, /OPEN BAY APPROACH/)
  assert.match(view.detail, /480 KM FROM STARBASE CENTER/)
  assert.match(view.detail, /DOCKING UNAVAILABLE/)
  assert.match(stationWarningView({...base, level: "critical"}).label, /STARBASE HULL/)
  assert.match(stationWarningView({...base, level: "caution"}).label, /PROXIMITY/)
  assert.equal(stationWarningView({...base, level: "clear"}), null)
  assert.equal(stationWarningView({...base, distance_km: Infinity, level: "approach"}), null)
})
