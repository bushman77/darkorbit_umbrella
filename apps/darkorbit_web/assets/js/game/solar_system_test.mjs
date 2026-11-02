import assert from "node:assert/strict"
import test from "node:test"
import {
  SOLAR_BODIES, SOLAR_FOCUSES, SOLAR_SYSTEM_ID, findSolarBody,
  solarLayout, orbitRadius, solarBodySummary, bodiesForFocus,
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
