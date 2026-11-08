import test from "node:test"
import assert from "node:assert/strict"
import {readFileSync} from "node:fs"

const game = readFileSync(new URL("./client.js", import.meta.url), "utf8")
const markup = readFileSync(new URL(
  "../../../lib/darkorbit_web/controllers/game_html/show.html.heex", import.meta.url),
"utf8")

test("destroyed pilots get an actionable Earth recovery prompt, including after reconnect", () => {
  assert.match(markup, /id="pilot-respawn-panel"/)
  assert.match(markup, /id="pilot-respawn-button"/)
  assert.match(game, /this\.entities\.get\(this\.selfId\)\?\.status === "destroyed"/)
  assert.match(game, /this\.showRespawnPanel\(true, impact/)
  assert.match(game, /this\.requestRespawn\(\)/)
})

test("respawn does not choose coordinates or trust any client-selected planet", () => {
  assert.match(game, /old\.push\("respawn", \{\}, 10_000\)/)
  assert.match(game, /if \(!validOrbitalMapId\(mapId\)\)/)
  assert.match(game, /old\.leave\(\)\.receive\("ok", rejoin\)/)
  assert.match(game, /this\.joinSector\(mapId\)/)
})

test("destroyed-state overlay leaves navigation and flight gating server-owned", () => {
  assert.match(game, /this\.flightControls\?\.release\(\{silent: true\}\)/)
  assert.match(game, /this\.worldStream = null/)
  assert.match(game, /this\.setSolarEncounter\(null\)/)
})
