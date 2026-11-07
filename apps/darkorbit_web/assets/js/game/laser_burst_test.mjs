import assert from "node:assert/strict"
import test from "node:test"
import {applyLaserBurstDamage, visualLaserRays} from "./laser_burst.mjs"

const enemy = id => ({
  id, kind: "npc", hull: 800, maxHull: 800, shields: 400,
  maxShields: 400, status: "alive", render: {x: 1500, y: 900, z: 0},
})
const state = (id, hull, shields) => ({
  id, hull, max_hull: 800, shields, max_shields: 400, status: "alive",
})

test("paired server laser event draws two symmetric beams and preserves hits", () => {
  const shot = {
    attacker_id: "pilot",
    hit: true,
    beams: [
      {side: "left", from: {x: 971, y: 950, z: 22},
       to: {x: 971, y: 790, z: 22}, hit: true},
      {side: "right", from: {x: 1029, y: 950, z: 22},
       to: {x: 1029, y: 790, z: 22}, hit: true},
    ],
  }
  const rays = visualLaserRays(shot)
  assert.equal(rays.length, 2)
  assert.deepEqual(rays.map(ray => ray.side), ["left", "right"])
  assert.equal(rays[0].from.y, rays[1].from.y)
  assert.equal(rays[0].from.z, rays[1].from.z)
  assert.ok(rays.every(ray => ray.hit))
})

test("two target impacts update shield and hull from server-owned results", () => {
  const targets = new Map([["npc1",enemy("npc1")],["npc2",enemy("npc2")]])
  const attack = {
    hit: true,
    hits: [
      {target_id: "npc1", target: state("npc1", 795, 385)},
      {target_id: "npc2", target: state("npc2", 798, 382)},
    ],
  }
  assert.equal(applyLaserBurstDamage(targets,attack),2)
  assert.equal(targets.get("npc1").shields,385)
  assert.equal(targets.get("npc2").hull,798)
})

test("double hit on same target applies final damage exactly once", () => {
  const targets=new Map([["npc1",enemy("npc1")]])
  const attack={hits:[{target_id:"npc1",target:state("npc1",784,376)}]}
  assert.equal(applyLaserBurstDamage(targets,attack),1)
  assert.equal(targets.get("npc1").shields,376)
  assert.equal(targets.get("npc1").hull,784)
})

test("miss shows both wing beams and does not damage or fabricate targets", () => {
  const targets = new Map([["npc1",enemy("npc1")]])
  const attack = {
    hit: false, hits: [],
    beams: [
      {side:"left",from:{x:0,y:0,z:0},to:{x:0,y:-700,z:0},hit:false},
      {side:"right",from:{x:2,y:0,z:0},to:{x:2,y:-700,z:0},hit:false},
    ],
  }
  assert.equal(applyLaserBurstDamage(targets,attack),0)
  assert.equal(targets.get("npc1").hull,800)
  assert.equal(visualLaserRays(attack).length,2)
  assert.equal(visualLaserRays(attack).filter(beam=>beam.hit).length,0)
})

test("legacy non-burst NPC and player damage events are still supported", () => {
  const targets = new Map([["npc1",enemy("npc1")]])
  const attack = {target_id:"npc1", target:state("npc1",790,390), hit:true}
  assert.equal(applyLaserBurstDamage(targets,attack),1)
  assert.equal(targets.get("npc1").hull,790)
  assert.equal(visualLaserRays({...attack}, {render:{x:0,y:0,z:0}},
    targets.get("npc1")).length,1)
})
