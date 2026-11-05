import test from "node:test"
import assert from "node:assert/strict"
import {solarMenuTarget,canNavigateSolar} from "./solar_context_menu.mjs"

const idle={system_id:"sol",status:"idle",location_id:"earth"}

test("map right-click selects target or existing selection, not phantom coordinates",()=>{
  assert.equal(solarMenuTarget("mars","earth"),"mars")
  assert.equal(solarMenuTarget(null,"saturn"),"saturn")
  assert.equal(solarMenuTarget("missing","earth"),"earth")
  assert.equal(solarMenuTarget(null,"invalid"),null)
})
test("navigate action cannot bypass server course gating",()=>{
  assert.equal(canNavigateSolar("mars",idle,true,false),true)
  assert.equal(canNavigateSolar("earth",idle,true,false),false)
  assert.equal(canNavigateSolar("sun",idle,true,false),false)
  assert.equal(canNavigateSolar("mars",{...idle,status:"traveling"},true,false),false)
  assert.equal(canNavigateSolar("mars",idle,false,false),false)
  assert.equal(canNavigateSolar("mars",idle,true,true),false)
  assert.equal(canNavigateSolar("mars",null,true,false),false)
})
