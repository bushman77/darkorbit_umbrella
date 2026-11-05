import assert from "node:assert/strict"
import test from "node:test"
import {
  SOLAR_BODIES, SOLAR_FOCUSES, SOLAR_SYSTEM_ID, findSolarBody,
  solarLayout, orbitRadius, solarBodySummary, bodiesForFocus,
  solarGameRadius, solarPositionToChart, solarChartToPosition,
} from "./solar_system.mjs"

test("Sun, all eight planets and Pluto appear in heliocentric order", () => {
  assert.equal(SOLAR_SYSTEM_ID,"sol")
  assert.deepEqual(SOLAR_BODIES.map(b=>b.name),[
    "Sun","Mercury","Venus","Earth","Mars","Jupiter",
    "Saturn","Uranus","Neptune","Pluto",
  ])
  assert.equal(SOLAR_BODIES.filter(b=>b.kind==="planet").length,8)
  assert.equal(findSolarBody("pluto").kind,"dwarf_planet")
  assert.equal(findSolarBody("nonesuch"),null)
  assert.deepEqual(SOLAR_BODIES.map(b=>b.au),[...SOLAR_BODIES.map(b=>b.au)].sort((a,b)=>a-b))
})

test("astronomical distances remain AU and separate from Sector 1-1 coordinates",()=>{
  assert.equal(findSolarBody("earth").au,1)
  assert.ok(findSolarBody("jupiter").au > 5)
  assert.ok(findSolarBody("pluto").au > 39)
  assert.equal(findSolarBody("sun").au,0)
  assert.equal(solarBodySummary(findSolarBody("pluto")).classification,"Dwarf planet")
  assert.equal(solarBodySummary(findSolarBody("pluto")).distance,"39.482 AU")
  assert.equal(solarBodySummary(findSolarBody("sun")).distance,"System center")
})

test("compressed system diagram shows all orbits without dropping inner planets",()=>{
  const bodies=solarLayout("system")
  assert.equal(bodies.length,10)
  for(const body of bodies){
    assert.ok(Number.isFinite(body.x)&&Number.isFinite(body.y))
    assert.ok(body.x>200&&body.x<800&&body.y>0&&body.y<600)
  }
  assert.ok(orbitRadius(0.387,"system")>20)
  assert.ok(orbitRadius(39.482,"system")<300)
  assert.equal(orbitRadius(0),0)
  assert.equal(orbitRadius(-5),null)
  assert.equal(orbitRadius(NaN),null)
})

test("inner system magnification preserves Sun-to-Mars order and body identities",()=>{
  assert.deepEqual(SOLAR_FOCUSES,["system","inner"])
  assert.deepEqual(bodiesForFocus("inner").map(b=>b.id),[
    "sun","mercury","venus","earth","mars",
  ])
  const inner=solarLayout("inner")
  assert.equal(inner.length,5)
  assert.ok(inner[1].orbitRadius>orbitRadius(0.387,"system"))
  assert.ok(inner[4].orbitRadius>inner[3].orbitRadius)
  assert.equal(solarLayout("system")[9].id,"pluto")
})

test("diagram uses only explicitly schematic phases, not current astronomy",()=>{
  assert.ok(SOLAR_BODIES.every(body=>Number.isFinite(body.phase)))
  assert.ok(SOLAR_BODIES.every(body=>typeof body.color==="string"))
  assert.equal(solarBodySummary(null),null)
})

test("SOL world game-km coordinates round-trip through both Atlas projections",()=>{
  for (const focus of SOLAR_FOCUSES) {
    for (const body of bodiesForFocus(focus).filter(b=>b.au>0)) {
      const angle=body.phase*Math.PI/180
      const radius=solarGameRadius(body.au)
      const position={x:radius*Math.cos(angle),y:radius*Math.sin(angle),z:0}
      const plotted=solarPositionToChart(position,focus)
      const marker=solarLayout(focus).find(b=>b.id===body.id)
      assert.ok(Math.abs(plotted.x-marker.x)<.00001,body.name)
      assert.ok(Math.abs(plotted.y-marker.y)<.00001,body.name)
      const back=solarChartToPosition(plotted.x,plotted.y,focus,position.z)
      assert.ok(Math.hypot(back.x-position.x,back.y-position.y)<.01,body.name)
    }
    const remote={x:-68_000_000,y:65_000_000,z:120}
    const plotted=solarPositionToChart(remote,focus)
    const back=solarChartToPosition(plotted.x,plotted.y,focus,120)
    assert.ok(Math.hypot(back.x-remote.x,back.y-remote.y)<.1)
    assert.equal(back.z,120)
  }
  assert.equal(solarChartToPosition(NaN,20),null)
  assert.equal(solarPositionToChart({x:NaN,y:5,z:0}),null)
})
