import test from "node:test"
import assert from "node:assert/strict"
import {solarMenuTarget,canNavigateSolar,validSolarWaypoint} from "./solar_context_menu.mjs"

const idle={system_id:"sol",status:"idle",location_id:"earth",position_km:{x:10000000,y:10000000,z:0}}
const waypoint={x:13000000,y:10000000,z:0}

test("right click empty space returns its own world coordinate, never a selected planet",()=>{
  assert.equal(solarMenuTarget("mars","earth",waypoint),"mars")
  assert.deepEqual(solarMenuTarget(null,"saturn",waypoint),waypoint)
  assert.equal(solarMenuTarget("missing","earth"),null)
  assert.equal(solarMenuTarget(null,"earth",{x:0,y:0,z:0}),null)
})
test("named and free destinations obey authoritative course gating",()=>{
  assert.equal(canNavigateSolar("mars",idle,true,false),true)
  assert.equal(canNavigateSolar(waypoint,idle,true,false),true)
  assert.equal(canNavigateSolar("earth",idle,true,false),false)
  assert.equal(canNavigateSolar("sun",idle,true,false),false)
  assert.equal(canNavigateSolar(waypoint,{...idle,status:"traveling"},true,false),false)
  assert.equal(canNavigateSolar("mars",idle,false,false),false)
  assert.equal(canNavigateSolar("mars",idle,true,true),false)
  assert.equal(canNavigateSolar("mars",null,true,false),false)
  assert.equal(validSolarWaypoint({x:0,y:0,z:0}),false)
  assert.equal(validSolarWaypoint({x:300000000,y:0,z:0}),false)
  assert.equal(canNavigateSolar(idle.position_km,idle,true,false),false)
})
