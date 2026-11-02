import assert from "node:assert/strict"
import test from "node:test"
import {NavigationComputer} from "./navigation_computer.mjs"

const fakeRoot=()=>{
  const nodes=new Map()
  const element=(id)=>{
    const node={
      hidden:false,textContent:"",attrs:{},classes:new Set(),
      setAttribute(key,value){this.attrs[key]=String(value)},
      classList:{toggle(name,enabled){
        if(enabled)node.classes.add(name)
        else node.classes.delete(name)
      }},
    }
    nodes.set(id,node)
    return node
  }
  for(const id of [
    "#nav-solar-view","#nav-sector-view","#nav-view-system",
    "#nav-view-sector","#nav-title","#nav-subtitle",
  ])element(id)
  return {nodes,root:{
    querySelector:key=>nodes.get(key)||null,
    querySelectorAll:()=>[],
  }}
}

test("system Atlas opens first and sector chart remains a separate view",()=>{
  const {nodes,root}=fakeRoot()
  const nav=new NavigationComputer({
    root,getEntities:()=>new Map(),getSelfId:()=>null,
    getBoundaries:()=>({width:20000,height:12000}),
    isConnected:()=>false,engage:()=>{},halt:()=>{},
  })
  assert.equal(nav.view,"system")
  assert.equal(nav.solarSelection,"earth")
  nav.setView("sector")
  assert.equal(nodes.get("#nav-solar-view").hidden,true)
  assert.equal(nodes.get("#nav-sector-view").hidden,false)
  assert.equal(nodes.get("#nav-view-sector").attrs["aria-selected"],"true")
  assert.match(nodes.get("#nav-title").textContent,/Sector 1-1/)
  nav.setView("system")
  assert.equal(nodes.get("#nav-sector-view").hidden,true)
  assert.equal(nodes.get("#nav-solar-view").hidden,false)
  assert.match(nodes.get("#nav-title").textContent,/Solar System/)
})

test("planet selection does not corrupt sector waypoints or create fake routes",()=>{
  const {root}=fakeRoot()
  const nav=new NavigationComputer({
    root,getEntities:()=>new Map(),getSelfId:()=>null,
    getBoundaries:()=>({width:20000,height:12000}),
    isConnected:()=>false,engage:()=>{},halt:()=>{},
  })
  nav.draft=[{x:1_200,y:1_300,z:20}]
  nav.selectSolarBody("pluto")
  assert.equal(nav.solarSelection,"pluto")
  assert.deepEqual(nav.draft,[{x:1_200,y:1_300,z:20}])
  nav.setSolarFocus("inner")
  assert.equal(nav.solarSelection,"earth")
  nav.setSolarFocus("system")
  nav.selectSolarBody("saturn")
  assert.equal(nav.solarSelection,"saturn")
  assert.deepEqual(nav.draft,[{x:1_200,y:1_300,z:20}])
  nav.selectSolarBody("bad-id")
  assert.equal(nav.solarSelection,"saturn")
})
