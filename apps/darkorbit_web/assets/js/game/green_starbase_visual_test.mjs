import test from "node:test"
import assert from "node:assert/strict"
import {GreenStarbaseVisual, starbaseVisible} from "./green_starbase_visual.js"

const nearby = {
  status:"idle", location_id:null,green_starbase_nearby:true,
  starbases:[{id:"sol:starbase:green",model:"green_pyramid_starbase_v1",
    site_3d:{x:12000,y:15500,z:0}}],
}

test("the station only appears in its authenticated deep-space region",()=>{
  assert.equal(starbaseVisible(nearby,"sol:free_15"),true)
  assert.equal(starbaseVisible({...nearby,green_starbase_nearby:false},"sol:free_15"),false)
  assert.equal(starbaseVisible({...nearby,status:"traveling"},"sol:free_15"),false)
  assert.equal(starbaseVisible({...nearby,location_id:"mars"},"sol:free_15"),false)
  assert.equal(starbaseVisible(nearby,"sol:earth"),false)
  assert.equal(starbaseVisible({...nearby,starbases:[]},"sol:free_15"),false)
})

class Group {
  constructor(){this.children=[];this.position={set:(...xs)=>{this.at=xs}};
    this.userData={}}
  add(child){this.children.push(child)}
}
class Mesh {
  constructor(geometry,material){this.geometry=geometry;this.material=material;
    this.position={set:(...xs)=>{this.at=xs}};
    this.rotation={set:()=>{}}}
}
class Resource {
  constructor(...args){this.args=args}
  dispose(){this.disposed=true}
}
const THREE={
  Group,Mesh,ConeGeometry:Resource,BoxGeometry:Resource,
  CylinderGeometry:Resource,MeshBasicMaterial:Resource,
  MeshStandardMaterial:Resource,
}
test("procedural mesh is one reusable node with an actual open front and disposal",()=>{
  const scene={children:[],add(n){this.children.push(n)},
    remove(n){this.children=this.children.filter(x=>x!==n)}}
  const visual=new GreenStarbaseVisual(THREE,scene)
  visual.update(nearby,"sol:free_15")
  assert.equal(scene.children.length,1)
  assert.equal(visual.node.visible,true)
  assert.ok(visual.node.children.length>=20)
  const meshes=visual.node.children
  assert.equal(meshes.filter(m=>m.geometry.args[2]===4 && m.geometry.args.length===3).length,2)
  // Four lines on the rectangular aperture, no opaque front bulkhead.
  assert.equal(meshes.filter(m=>m.material===visual.materials[4] &&
    m.geometry.args[2]===0.8).length,4)
  const geometry=visual.geometries[0]
  visual.update(nearby,"sol:free_15")
  assert.equal(scene.children.length,1)
  visual.update({...nearby,green_starbase_nearby:false},"sol:free_15")
  assert.equal(visual.node.visible,false)
  visual.dispose()
  assert.equal(scene.children.length,0)
  assert.equal(geometry.disposed,true)
})
