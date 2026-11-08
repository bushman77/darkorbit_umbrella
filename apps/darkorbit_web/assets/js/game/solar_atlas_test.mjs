import assert from "node:assert/strict"
import test from "node:test"
import {drawSolarAtlas,renderSolarDetails} from "./solar_atlas.mjs"
import {findSolarBody,solarLayout} from "./solar_system.mjs"

const fakeNode = (type="div") => ({
  type,attrs:{},children:[],textContent:"",style:{},dataset:{},
  setAttribute(name,value){this.attrs[name]=String(value)},
  getAttribute(name){return this.attrs[name]??null},
  appendChild(child){this.children.push(child);return child},
  append(...children){this.children.push(...children)},
  replaceChildren(...children){this.children=[...children]},
})

const withDocument = fn => {
  const previous=globalThis.document
  globalThis.document={
    createElement:tag=>fakeNode(tag),
    createElementNS:(_ns,tag)=>fakeNode(tag),
  }
  try{return fn()}finally{globalThis.document=previous}
}

test("Solar Atlas draws Sun through Pluto with selectable SVG markers",()=>{
  withDocument(()=>{
    const layer=fakeNode("g")
    const svg={querySelector:q=>q==="#nav-solar-content"?layer:null}
    drawSolarAtlas(svg,{selectedId:"pluto"})
    const groups=layer.children.filter(node=>node.attrs["data-body-id"])
    assert.equal(groups.length,10)
    assert.deepEqual(groups.map(group=>group.attrs["data-body-id"]),
      solarLayout().map(body=>body.id))
    const pluto=groups.find(group=>group.attrs["data-body-id"]==="pluto")
    assert.equal(pluto.attrs["aria-pressed"],"true")
    assert.equal(pluto.attrs.tabindex,"0")
    assert.ok(layer.children.filter(node=>node.type==="circle").length>150)
  })
})

test("inner magnification shows Sun and terrestrial planets without lying about AU",()=>{
  withDocument(()=>{
    const layer=fakeNode("g")
    const svg={querySelector:q=>q==="#nav-solar-content"?layer:null}
    drawSolarAtlas(svg,{focus:"inner",selectedId:"earth"})
    const markers=layer.children.filter(node=>node.attrs["data-body-id"])
    assert.deepEqual(markers.map(item=>item.attrs["data-body-id"]),[
      "sun","mercury","venus","earth","mars",
    ])
    const earth=markers.find(item=>item.attrs["data-body-id"]==="earth")
    assert.equal(earth.attrs["aria-pressed"],"true")
    assert.equal(findSolarBody("earth").au,1)
  })
})

test("clickable body list and selected details include Pluto's classification",()=>{
  withDocument(()=>{
    const views=Object.fromEntries([
      "#nav-solar-name","#nav-solar-type","#nav-solar-distance",
      "#nav-solar-period","#nav-system-bodies",
    ].map(key=>[key,fakeNode()]))
    const root={querySelector:key=>views[key]||null}
    renderSolarDetails(root,"pluto")
    assert.equal(views["#nav-solar-name"].textContent,"Pluto")
    assert.equal(views["#nav-solar-type"].textContent,"Dwarf planet")
    assert.equal(views["#nav-solar-distance"].textContent,"39.482 AU")
    const list=views["#nav-system-bodies"].children
    assert.equal(list.length,10)
    assert.equal(list[9].dataset.bodyId,"pluto")
    assert.equal(list[9].attrs["aria-pressed"],"true")
    assert.equal(list[0].attrs["aria-pressed"],"false")
  })
})

test("server-owned transit draws travel vector and interpolated pilot marker",()=>{
  withDocument(()=>{
    const layer=fakeNode("g")
    const svg={querySelector:q=>q==="#nav-solar-content"?layer:null}
    drawSolarAtlas(svg,{selectedId:"mars",navigation:{
      system_id:"sol",status:"traveling",location_id:"earth",
      destination_id:"mars",progress:.5,
    }})
    const path=layer.children.find(child=>
      child.type==="line"&&child.attrs["stroke"]==="#67f4ee")
    assert.ok(path)
    const marker=layer.children.find(child=>
      child.type==="circle"&&child.attrs["stroke"]==="#a8ffff")
    assert.ok(marker)
    const earth=solarLayout().find(b=>b.id==="earth")
    const mars=solarLayout().find(b=>b.id==="mars")
    assert.ok(Math.abs(Number(marker.attrs.cx)-(earth.x+mars.x)/2)<.0001)
    assert.ok(Math.abs(Number(marker.attrs.cy)-(earth.y+mars.y)/2)<.0001)
  })
})

// A starbase is not an extra planet; the Atlas draws it as a separate
// navigable object using the server-supplied coordinate.
test("independent Green Starbase renders as a selected twin-pyramid Atlas marker",()=>{
  withDocument(()=>{
    const layer=fakeNode("g")
    const svg={querySelector:q=>q==="#nav-solar-content"?layer:null}
    const site={id:"sol:starbase:green",name:"Green Starbase",
      kind:"starbase",position_km:{x:-9_957_476,y:-849_608,z:0}}
    drawSolarAtlas(svg,{selectedId:"earth",selectedStarbaseId:site.id,
      navigation:{system_id:"sol",status:"idle",starbases:[site]}})
    const marker=layer.children.find(node=>node.attrs["data-starbase-id"]===site.id)
    assert.ok(marker)
    assert.equal(marker.attrs["aria-pressed"],"true")
    assert.equal(marker.children.filter(n=>n.type==="polygon").length,2)
    assert.equal(marker.children.filter(n=>n.type==="rect").length,2)
    assert.equal(layer.children.filter(n=>n.attrs["data-body-id"]).length,10)
  })
})
