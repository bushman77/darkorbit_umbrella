import test from "node:test"
import assert from "node:assert/strict"
import {readFileSync} from "node:fs"

const html = readFileSync(new URL("../ui/index.html", import.meta.url), "utf8")
const css = readFileSync(new URL("../ui/launcher.css", import.meta.url), "utf8")

test("the desktop launcher uses the shared HUD layout", () => {
  assert.match(html, /class="launcher-stage"/)
  assert.match(html, /class="launcher-rail"/)
  assert.match(html, /class="launcher-briefing"/)
  assert.match(html, /class="launcher-console"/)
  assert.match(css, /\.launcher-stage/)
  assert.match(css, /\.launcher-commandbar/)
})

test("all connection controls are preserved for the launcher controller", () => {
  for (const id of ["connect-form", "server-url", "use-local", "register-pilot", "visit-home", "error", "networking-open", "networking-panel", "proxy-mode", "proxy-host", "proxy-port", "networking-form"]) {
    assert.equal((html.match(new RegExp('id="' + id + '"', "g")) ?? []).length, 1, id)
  }
  assert.match(html, /type="submit"/)
  assert.match(html, /https:\/\/spacenova\.ddns\.net/)
  assert.match(html, /http:\/\/127\.0\.0\.1:4000/)
})

test("only the local launcher includes native networking commands", () => {
  const js = readFileSync(new URL("../ui/networking.mjs", import.meta.url), "utf8")
  assert.match(js, /get_network_settings/)
  assert.match(js, /save_network_settings/)
  assert.match(js, /restart_client/)
  assert.doesNotMatch(js, /danger_accept_invalid_certs|ignore_certificate_errors/)
})
