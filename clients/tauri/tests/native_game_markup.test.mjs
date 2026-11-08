import test from "node:test"
import assert from "node:assert/strict"
import {readFileSync} from "node:fs"
import {convertGameMarkup, nativeGameDocument} from "../scripts/native-game-markup.mjs"

const template = readFileSync(new URL("../../../apps/darkorbit_web/lib/darkorbit_web/controllers/game_html/show.html.heex", import.meta.url), "utf8")
const markup = convertGameMarkup(template)
const document = nativeGameDocument(markup)

test("standalone markup contains the real Atlas and 3D/SBS cockpit", () => {
  for (const id of ["game-client", "space-viewport-3d", "navigation-computer",
    "nav-solar-chart", "display-mode", "action-hotbar", "pilot-logout-form"]) {
    assert.match(document, new RegExp('id="' + id + '"'))
  }
  assert.match(document, /data-native-client="true"/)
  assert.match(document, /data-server-origin=""/)
  assert.match(document, /native_game.css/)
  assert.match(document, /native_bootstrap.mjs/)
  assert.match(document, /native-login-form/)
})

test("native renderer has exactly ten server-populated hotbar placeholders", () => {
  for (let slot = 1; slot <= 10; slot++) {
    assert.match(markup, new RegExp('id="hotbar-slot-' + slot + '"'))
  }
  assert.equal((markup.match(/data-hotbar-slot="/g) || []).length, 10)
  assert.equal((markup.match(/data-hotbar-label/g) || []).length, 10)
})

test("no EEx expressions, server forms or remote asset links remain", () => {
  assert.doesNotMatch(document, /<%|<\.icon|<\.form|<\/\.form|{\@|{~p/)
  assert.doesNotMatch(document, /href="\/equipment"/)
  assert.doesNotMatch(document, /src="https?:\/\//)
})

test("native bootstrap uses authenticated API without persisting pilot tokens", () => {
  const js = readFileSync(new URL("../ui/native_bootstrap.mjs", import.meta.url), "utf8")
  assert.match(js, /\/api\/native\/login/)
  assert.match(js, /\/api\/native\/refresh/)
  assert.match(js, /\/api\/native\/logout/)
  assert.match(js, /nativePostJson/)
  assert.match(js, /import\("\.\/native_game\.js"\)/)
  assert.doesNotMatch(js, /localStorage\.setItem\(.*token/)
})

test("native markup generation is identical with Windows CRLF and Unix LF", () => {
  const unix = template.replace(/\r\n?/g, "\n")
  assert.equal(convertGameMarkup(unix.replace(/\n/g, "\r\n")), markup)
})
