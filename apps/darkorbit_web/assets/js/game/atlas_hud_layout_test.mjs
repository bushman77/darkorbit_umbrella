import test from "node:test"
import assert from "node:assert/strict"
import {clampHudPosition} from "./atlas_hud_layout.mjs"

test("HUD stays inside screen bounds",()=>{
  assert.deepEqual(clampHudPosition(-200,-40,1400,900,260,280),{left:8,top:64})
  assert.deepEqual(clampHudPosition(5000,5000,1400,900,260,280),{left:1132,top:574})
  assert.deepEqual(clampHudPosition(400,300,1400,900,260,280),{left:400,top:300})
})
test("small windows still provide finite, on-screen positions",()=>{
  const pos=clampHudPosition(900,900,350,350,330,320)
  assert.deepEqual(pos,{left:12,top:64})
})
