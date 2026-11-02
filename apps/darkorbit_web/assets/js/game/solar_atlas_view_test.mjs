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

test("starting in Solar System Atlas blocks cockpit controls until explicitly closed",()=>{
  const {nodes,root}=fakeRoot()
  let opens=0
  let closes=0
  // The actual map SVG renderer is covered by solar_atlas_test.mjs.
  // Here we test the modal's initial visibility and release lifecycle.
  const closer={
    ...root.querySelector("#nav-view-system"),
    focus(){this.focused=true},
  }
  nodes.set("#nav-close",closer)
  nodes.set("#nav-z",{min:"",max:"",value:""})
  root.hidden=false // server markup presents the Atlas before JS loads
  const nav=new NavigationComputer({
    root,getEntities:()=>new Map(),getSelfId:()=>null,
    getBoundaries:()=>({width:20000,height:12000,altitude_min:-3000,altitude_max:3000}),
    isConnected:()=>false,engage:()=>{},halt:()=>{},
    onOpen:()=>{opens++},onClose:()=>{closes++},
  })
  // Stub the visual renderer only; open() must still execute setView().
  nav.renderSolarView=()=>{}
  nav.open()
  assert.equal(nav.isOpen,true)
  assert.equal(root.hidden,false)
  assert.equal(nav.view,"system")
  assert.equal(nodes.get("#nav-sector-view").hidden,true)
  assert.equal(nodes.get("#nav-solar-view").hidden,false)
  assert.equal(closer.focused,true)
  assert.equal(opens,1)
  nav.open() // idempotent, including its flight release callback
  assert.equal(opens,1)
  nav.close()
  assert.equal(nav.isOpen,false)
  assert.equal(root.hidden,true)
  assert.equal(closes,1)
  nav.close()
  assert.equal(closes,1)
})

test("SOL course controls use authenticated callbacks without touching sector route",()=>{
  const {nodes,root}=fakeRoot()
  const added=["#nav-solar-state","#nav-solar-location","#nav-solar-route",
    "#nav-solar-progress","#nav-solar-progress-label",
    "#nav-solar-engage","#nav-solar-cancel"]
  for(const id of added)nodes.set(id,{textContent:"",disabled:false,value:0})
  const calls=[]
  const nav=new NavigationComputer({
    root,getEntities:()=>new Map(),getSelfId:()=>42,
    getBoundaries:()=>({width:20000,height:12000}),
    isConnected:()=>true,engage:()=>{},halt:()=>{},
    solarSetCourse:(body,done)=>{calls.push(body);done(true,{
      system_id:"sol",location_id:"earth",origin_id:"earth",status:"traveling",
      destination_id:body,progress:0,remaining_ms:12000,
    })},
    solarCancelCourse:done=>{calls.push("abort");done(true,{
      system_id:"sol",location_id:"earth",origin_id:"earth",status:"idle",
      destination_id:null,progress:0,remaining_ms:0,
    })},
  })
  nav.isOpen=true
  nav.renderSolarView=()=>nav.renderSolarNavigation()
  nav.draft=[{x:1400,y:1200,z:100}]
  nav.setSolarNavigation({system_id:"sol",location_id:"earth",
    status:"idle",progress:0})
  assert.equal(nodes.get("#nav-solar-location").textContent,"Earth")
  nav.selectSolarBody("mars")
  nav.engageSolarCourse()
  assert.deepEqual(calls,["mars"])
  assert.equal(nav.solarNavigation.status,"traveling")
  assert.equal(nodes.get("#nav-solar-engage").disabled,true)
  assert.equal(nodes.get("#nav-solar-route").textContent,"Earth → Mars")
  nav.setSolarNavigation({...nav.solarNavigation,progress:.5,remaining_ms:6000})
  assert.equal(nodes.get("#nav-solar-progress").value,50)
  nav.cancelSolarCourse()
  assert.deepEqual(calls,["mars","abort"])
  assert.equal(nav.solarNavigation.status,"idle")
  assert.deepEqual(nav.draft,[{x:1400,y:1200,z:100}])
})

test("Sun cannot be a travel destination and missing relay disables SOL commands",()=>{
  const {nodes,root}=fakeRoot()
  for(const id of ["#nav-solar-state","#nav-solar-location","#nav-solar-route",
    "#nav-solar-progress","#nav-solar-progress-label","#nav-solar-engage",
    "#nav-solar-cancel"])nodes.set(id,{textContent:"",disabled:false,value:0})
  const requests=[]
  const nav=new NavigationComputer({
    root,getEntities:()=>new Map(),getSelfId:()=>42,
    getBoundaries:()=>({width:20000,height:12000}),
    isConnected:()=>false,engage:()=>{},halt:()=>{},
    solarSetCourse:id=>requests.push(id),
  })
  nav.isOpen=true
  nav.renderSolarView=()=>nav.renderSolarNavigation()
  nav.setSolarNavigation({system_id:"sol",status:"idle",location_id:"earth"})
  nav.selectSolarBody("mars")
  nav.engageSolarCourse()
  assert.equal(nodes.get("#nav-solar-engage").disabled,true)
  nav.selectSolarBody("sun")
  nav.engageSolarCourse()
  assert.deepEqual(requests,[])
})
