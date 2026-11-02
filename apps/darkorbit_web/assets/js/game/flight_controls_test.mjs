import assert from "node:assert/strict"
import test from "node:test"
import {FlightControls} from "./flight_controls.mjs"

const press = (code, extras = {}) => ({code, repeat:false, defaultPrevented:false,
  preventDefault(){this.prevented=true}, ...extras})

test("W increases and S decreases throttle including into reverse", () => {
  let time = 1000
  const events = []
  const flight = new FlightControls({send: value => events.push(value), now: () => time})
  flight.keyDown(press("KeyW"))
  assert.equal(flight.throttle, 0.1)
  for (let i = 0; i < 5; i++) {
    time += 125
    flight.heartbeat(time)
  }
  assert.equal(flight.throttle,0.6)
  flight.keyUp(press("KeyW"))
  time += 125
  flight.keyDown(press("KeyS"))
  for (let i = 0; i < 13; i++) {
    time += 125
    flight.heartbeat(time)
  }
  assert.equal(flight.throttle, -0.8)
  flight.keyUp(press("KeyS"))
  assert.equal(events.at(-1).throttle,-0.8)
})

test("plus/minus still adjust signed throttle in steps and clamp", () => {
  let time=1000
  const flight=new FlightControls({send:()=>{}, now:()=>time})
  for(let i=0;i<15;i++) {flight.keyDown(press("Minus"));time+=125}
  assert.equal(flight.throttle,-1)
  for(let i=0;i<10;i++) {flight.keyDown(press("Equal"));time+=125}
  assert.equal(flight.throttle,0)
  flight.keyDown(press("NumpadAdd"))
  assert.equal(flight.throttle,0.1)
})

test("A/D strictly yaw; arrows pitch; Z/C strictly roll", () => {
  const flight=new FlightControls({send:()=>{}, now:()=>2000})
  flight.keyDown(press("KeyD"))
  assert.deepEqual(flight.axes(),{yaw:1,pitch:0,roll:0})
  flight.keyDown(press("ArrowUp"))
  assert.deepEqual(flight.axes(),{yaw:1,pitch:1,roll:0})
  flight.keyDown(press("KeyC"))
  assert.deepEqual(flight.axes(),{yaw:1,pitch:1,roll:1})
  flight.keyUp(press("KeyD"))
  assert.equal(flight.axes().yaw,0)
  flight.keyDown(press("KeyF"))
  assert.deepEqual(flight.axes(),{yaw:0,pitch:0,roll:0})
})

test("Ctrl+E toggles modes; typing is protected", () => {
  let count=0
  const flight=new FlightControls({send:()=>count++,now:()=>2000})
  assert.equal(flight.keyDown(press("KeyE",{ctrlKey:true})),true)
  assert.equal(flight.mode,"newtonian")
  flight.keyDown(press("KeyE",{ctrlKey:true,repeat:true}))
  assert.equal(flight.mode,"newtonian")
  assert.equal(flight.keyDown(press("KeyW",{target:{tagName:"INPUT"}})),false)
  assert.equal(flight.throttle,0)
  assert.equal(count,1)
})

test("held axis heartbeats, focus loss releases, atlas release is silent", () => {
  let time=2000
  const events=[]
  const flight=new FlightControls({send: p=>events.push(p),now:()=>time})
  flight.keyDown(press("KeyA"))
  assert.equal(events.length,1)
  time+=310
  flight.heartbeat(time)
  assert.equal(events.length,2)
  flight.release()
  assert.equal(events.at(-1).yaw,0)
  flight.keyDown(press("KeyC"))
  const count=events.length
  flight.release({silent:true})
  assert.equal(events.length,count)
  assert.deepEqual(flight.axes(),{yaw:0,pitch:0,roll:0})
})
