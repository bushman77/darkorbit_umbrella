import test from "node:test"
import assert from "node:assert/strict"
import {readFileSync} from "node:fs"

const read = name => readFileSync(new URL(name, import.meta.url), "utf8")
const game = read("./client.js")
const stereo = read("./stereo_view.js")
const helmet = read("./helmet_client.mjs")
const markup = read("../../../lib/darkorbit_web/controllers/game_html/show.html.heex")

test("desktop NPC conversation is keyboard accessible and server authorized", () => {
  assert.match(game, /handleStationNpcKey\(event\)/)
  assert.match(game, /event\.code !== "KeyE"/)
  assert.match(game, /this\.channel\.push\("station_talk", \{attendant_id: id, topic\}/)
  assert.match(game, /this\.stationWalking\?\.release\(\)/)
  assert.match(game, /nearestStationAttendant\(this\.stationPosition, this\.stationAttendants\)/)
  assert.match(game, /this\.root\.querySelector\("#station-npc-dialogue"\)/)
  assert.match(game, /button\.textContent = option\.label/)
  assert.match(markup, /id="station-npc-dialogue"/)
  assert.match(markup, /aria-modal="true"/)
  assert.match(markup, /id="station-npc-prompt"/)
})

test("the paired SBS viewer renders the same server-owned kiosk staff without commands", () => {
  assert.match(stereo, /this\.hangar\.update\(client\.stationPosition, time, client\.stationAttendants\)/)
  assert.match(helmet, /this\.stationAttendants = Array\.isArray\(map\.station_attendants\)/)
  assert.doesNotMatch(helmet, /channel\.push\("station_talk"/)
})

test("station console provides room labels and discloses non-operational services", () => {
  assert.match(markup, /Station attendants are present at each kiosk/)
  assert.match(markup, /purchases and repairs remain offline/)
})
