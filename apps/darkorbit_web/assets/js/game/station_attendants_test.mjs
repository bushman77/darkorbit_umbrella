import test from "node:test"
import assert from "node:assert/strict"
import {nearestStationAttendant} from "./station_attendants.mjs"

const npcs = [
  {id: "repair", room_id: "repair_bay", x: -49, z: -143},
  {id: "trade", room_id: "trade_exchange", x: 49, z: -143},
  {id: "missions", room_id: "mission_office", x: -16, z: -211},
]

test("only an attendant in the current room and physical range is prompted", () => {
  assert.equal(nearestStationAttendant(
    {room_id: "concourse", x: 49, z: -143}, npcs), null)
  assert.equal(nearestStationAttendant(
    {room_id: "trade_exchange", x: 49, z: -135}, npcs)?.id, "trade")
  assert.equal(nearestStationAttendant(
    {room_id: "trade_exchange", x: 49, z: -125}, npcs), null)
  assert.equal(nearestStationAttendant(
    {room_id: "mission_office", x: -16, z: -202}, npcs)?.id, "missions")
  assert.equal(nearestStationAttendant(null, npcs), null)
})

test("the local helper cannot turn a forged other-room contact into an interaction", () => {
  assert.equal(nearestStationAttendant(
    {room_id: "outfitting", x: -49, z: -143}, npcs), null)
  assert.equal(nearestStationAttendant(
    {room_id: "repair_bay", x: -49, z: -143}, npcs)?.id, "repair")
})
