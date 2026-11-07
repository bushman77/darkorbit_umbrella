import assert from "node:assert/strict"
import test from "node:test"
import {
  smoothOrientation, orientationTelemetry, rotateVector, normalizeOrientation,
} from "./orientation_interpolation.mjs"

const near = (actual, expected, tolerance = 1e-8) =>
  assert.ok(Math.abs(actual-expected) < tolerance, `${actual} != ${expected}`)
const angle = a => a*Math.PI/180
const axis = (name, degrees) => {
  const half=angle(degrees)/2
  return {x:name==="x"?Math.sin(half):0,
          y:name==="y"?Math.sin(half):0,
          z:name==="z"?Math.sin(half):0, w:Math.cos(half)}
}
const multiply = (a,b) => ({
  x:a.w*b.x + a.x*b.w + a.y*b.z - a.z*b.y,
  y:a.w*b.y - a.x*b.z + a.y*b.w + a.z*b.x,
  z:a.w*b.z + a.x*b.y - a.y*b.x + a.z*b.w,
  w:a.w*b.w - a.x*b.x - a.y*b.y - a.z*b.z,
})

test("slerp is smooth and approaches server orientation", () => {
  const east = axis("y",-90)
  let q = {x:0,y:0,z:0,w:1}
  const after = smoothOrientation(q,east,1/60)
  const nose = rotateVector(after,{x:0,y:0,z:-1})
  assert.ok(nose.x > 0 && nose.x < 1)
  for(let i=0;i<90;i++) q=smoothOrientation(i===0?after:q,east,1/60)
  near(rotateVector(q,{x:0,y:0,z:-1}).x,1,1e-5)
})

test("slerp handles equivalent opposite-signed quaternions without spinning", () => {
  const q=axis("z",90)
  const negative={x:-q.x,y:-q.y,z:-q.z,w:-q.w}
  const result=smoothOrientation(q,negative,1/60)
  near(Math.abs(result.z),Math.abs(q.z))
  near(Math.abs(result.w),Math.abs(q.w))
  assert.deepEqual(normalizeOrientation(null),null)
})

test("telemetry reads actual nose and bank after yaw and pitch", () => {
  const east=axis("y",-90)
  const raised=multiply(east,axis("x",30))
  const result=orientationTelemetry(raised)
  near(result.yaw,Math.PI/2)
  near(result.pitch,Math.PI/6)
  near(result.roll,0)
})

test("banked ship pitching moves nose horizontally, without world vertical pitch", () => {
  const banked=axis("z",90)
  const pitched=multiply(banked,axis("x",30))
  const nose=rotateVector(pitched,{x:0,y:0,z:-1})
  near(nose.x,-0.5)
  near(nose.y,0)
  near(nose.z,-Math.sqrt(3)/2)
  const values=orientationTelemetry(pitched)
  near(values.pitch,0)
  assert.ok(values.yaw < 0)
})

test("continuous 360-degree roll has no frozen world axes", () => {
  const q=axis("z",180)
  const orient=smoothOrientation({x:0,y:0,z:0,w:1},q,1/60)
  assert.ok(orient.w>0 && orient.w<1)
  near(Math.hypot(orient.x,orient.y,orient.z,orient.w),1)
})
