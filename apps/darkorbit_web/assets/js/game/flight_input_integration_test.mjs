import test from "node:test"
import assert from "node:assert/strict"
import {readFileSync} from "node:fs"

const client = readFileSync(new URL("./client.js", import.meta.url), "utf8")
const markup = readFileSync(new URL(
  "../../../lib/darkorbit_web/controllers/game_html/show.html.heex", import.meta.url),
"utf8")

test("keyboard and mouse share a single authoritative flight gate", () => {
  assert.match(client, /active: \(\) => this\.flightInputState\(\) === "ready"/)
  assert.match(client, /flightInputState\(\) \{[\s\S]*?sectorJoined:/)
})

test("native fallback mouse impulses must stop even without pointer lock", () => {
  assert.match(client, /document\.pointerLockElement !== this\.canvas && !this\.mouseFallback/)
  assert.match(client, /document\.pointerLockElement === this\.canvas \|\| this\.mouseFallback/)
})

test("cockpit shows an explicit manual helm takeover instead of silently altering cruise", () => {
  assert.match(markup, /id="cockpit-flight-input-status"/)
  assert.match(markup, /id="cockpit-take-helm"/)
  assert.match(client, /this\.solarEnterFreeFlight\(\(ok, navigation, reason\) =>/)
})
