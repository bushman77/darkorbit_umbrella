import test from "node:test"
import assert from "node:assert/strict"
import {readFileSync} from "node:fs"

const markup=readFileSync(new URL("../../../lib/darkorbit_web/controllers/game_html/show.html.heex",import.meta.url),"utf8")
const css=readFileSync(new URL("../../css/app.css",import.meta.url),"utf8")

test("Solar Atlas uses one full-screen map and independent HUD overlay",()=>{
  assert.match(markup,/class="nav-shell atlas-hud-shell"/)
  assert.match(markup,/class="atlas-hud-top"/)
  assert.match(markup,/id="nav-solar-view" class="solar-atlas-layout"/)
  assert.match(markup,/id="nav-flight-panel" class="hud-flight-widget"/)
  assert.match(markup,/id="nav-target-panel" class="solar-atlas-panel hud-target-widget"/)
  assert.doesNotMatch(markup,/class="solar-operations-panel"/)
  assert.match(css,/\.navigation-computer #nav-solar-chart \{/)
  assert.match(css,/\.navigation-computer #nav-sector-view .nav-layout \{/)
})

test("critical game, navigation and HUD controls remain unique",()=>{
  for(const id of [
    "nav-close","nav-view-system","nav-view-sector","nav-solar-chart",
    "nav-chart","nav-solar-engage","nav-solar-cancel","nav-solar-progress",
    "nav-traffic-contacts","nav-traffic-comms","nav-solar-context-menu",
    "nav-solar-context-target","nav-target-panel","nav-target-dismiss",
    "nav-hud-drag","nav-hud-reset","nav-solar-analysis","nav-system-bodies",
    "nav-helmet-open","nav-helmet-status","nav-mouse-steering",
  ]){
    const matches=markup.match(new RegExp('id="'+id+'"',"g"))??[]
    assert.equal(matches.length,1,id)
  }
  assert.match(markup,/id="nav-target-panel"[^>]*hidden>/s)
})
