import {
  SOLAR_BODIES, solarLayout, findSolarBody, solarBodySummary, solarClass,
  solarPositionToChart,
} from "./solar_system.mjs"

const NS="http://www.w3.org/2000/svg"

const svgElement = (name,attributes={},text=null) => {
  const node=document.createElementNS(NS,name)
  for(const [key,value] of Object.entries(attributes)) node.setAttribute(key,String(value))
  if(text!==null)node.textContent=String(text)
  return node
}

const add=(parent,name,attrs={},text=null)=>{
  const node=svgElement(name,attrs,text)
  parent.appendChild(node)
  return node
}

function renderOrbits(svg,layout,focus){
  add(svg,"rect",{x:0,y:0,width:1000,height:600,fill:"#04101f"})
  // Stable, lightweight starfield. No textures, requests or per-frame
  // animation; the system overview re-renders on explicit interaction.
  for(let i=0;i<150;i++){
    const x=(i*7919+47)%997
    const y=(i*4651+71)%593
    add(svg,"circle",{cx:x,cy:y,r:i%9===0?1.1:0.52,fill:"#b6d9f0",
      opacity:i%7===0?0.65:0.29})
  }
  // Subtle horizon crosshairs deliberately do not pretend to be a real chart
  // coordinate system. They're graphical orientation guides only.
  add(svg,"line",{x1:500,y1:16,x2:500,y2:584,stroke:"#163c54","stroke-dasharray":"5 10",opacity:0.6})
  add(svg,"line",{x1:200,y1:300,x2:800,y2:300,stroke:"#163c54","stroke-dasharray":"5 10",opacity:0.6})
  for(const body of layout){
    if(body.kind==="star")continue
    add(svg,"circle",{
      cx:500,cy:300,r:body.orbitRadius,fill:"none",
      stroke:body.id==="earth"?"#347b9d":"#24536d",
      "stroke-width":body.id==="earth"?1.8:1,
      "stroke-dasharray":body.id==="pluto"?"5 6":"none",
      opacity:body.id==="earth"?0.75:0.57,
    })
  }
  // This zone is a contextual reference, not an additional selectable
  // destination. The asteroid belt lies between Mars and Jupiter.
  if(focus==="system"){
    const belt=120
    add(svg,"circle",{cx:500,cy:300,r:belt,fill:"none",
      stroke:"#ad956d","stroke-width":9,"stroke-dasharray":"1 6",opacity:0.20})
  }
  add(svg,"text",{x:24,y:32,fill:"#88c4d7","font-size":15,
    "font-family":"monospace","letter-spacing":"2"},focus==="inner"?
    "SOL / INNER PLANETS":"SOL / FULL SYSTEM")
  add(svg,"text",{x:24,y:55,fill:"#6f9aaf","font-size":12,
    "font-family":"monospace"},"SCHEMATIC ORBITS · NOT LIVE POSITIONS")
  add(svg,"text",{x:24,y:580,fill:"#7494aa","font-size":12,
    "font-family":"monospace"},"AU VALUES REAL · DRAWING DISTANCES COMPRESSED")
}

function renderVoyage(svg,layout,navigation,focus){
  if(navigation?.system_id!=="sol")return
  const find=id=>layout.find(body=>body.id===id)
  const departure=navigation.origin_position_km
    ? solarPositionToChart(navigation.origin_position_km,focus)
    : find(navigation.location_id)
  const current=navigation.position_km
    ? solarPositionToChart(navigation.position_km,focus) : null
  if(navigation.status==="traveling"){
    const destination=navigation.destination_position_km
      ? solarPositionToChart(navigation.destination_position_km,focus)
      : find(navigation.destination_id)
    if(!departure||!destination)return
    const progress=Math.min(1,Math.max(0,Number(navigation.progress)||0))
    add(svg,"line",{x1:departure.x,y1:departure.y,
      x2:destination.x,y2:destination.y,stroke:"#67f4ee",
      "stroke-width":2.4,"stroke-dasharray":"6 7",opacity:.9})
    const x=current?.x??departure.x+(destination.x-departure.x)*progress
    const y=current?.y??departure.y+(destination.y-departure.y)*progress
    add(svg,"circle",{cx:x,cy:y,r:10,fill:"#07313b",stroke:"#a8ffff","stroke-width":2.5})
    add(svg,"circle",{cx:x,cy:y,r:3.5,fill:"#a8ffff"})
    add(svg,"text",{x:x+14,y:y-12,fill:"#b2ffff",
      "font-family":"monospace","font-size":13},"IN TRANSIT")
  }else{
    const here=current||find(navigation.location_id)
    if(!here)return
    add(svg,"circle",{cx:here.x,cy:here.y,r:12,
      fill:"none",stroke:"#73f5e8","stroke-width":1.8,opacity:.8})
    add(svg,"circle",{cx:here.x,cy:here.y,r:3,fill:"#73f5e8"})
  }
}

function renderWaypoint(svg,waypoint,focus){
  const point=solarPositionToChart(waypoint,focus)
  if(!point)return
  add(svg,"circle",{cx:point.x,cy:point.y,r:9,
    fill:"none",stroke:"#facc6c","stroke-width":2.2})
  add(svg,"line",{x1:point.x-14,y1:point.y,x2:point.x+14,y2:point.y,
    stroke:"#facc6c","stroke-width":1.2})
  add(svg,"line",{x1:point.x,y1:point.y-14,x2:point.x,y2:point.y+14,
    stroke:"#facc6c","stroke-width":1.2})
  add(svg,"text",{x:point.x+16,y:point.y-12,fill:"#facc6c",
    "font-family":"monospace","font-size":12},"FREE WAYPOINT")
}

// Server-owned independent starbases are navigational sites, not planets.
// Use their authoritative game-kilometre coordinate for the Atlas location.
export function renderStarbases(svg,starbases,focus,selectedStarbaseId=null) {
  for(const base of starbases || []) {
    if(base?.id!=="sol:starbase:green" || !base.position_km)continue
    const point=solarPositionToChart(base.position_km,focus)
    if(!point || !Number.isFinite(point.x) || !Number.isFinite(point.y))continue
    const {x,y}=point
    const selected=selectedStarbaseId===base.id
    const group=add(svg,"g",{"data-starbase-id":base.id,role:"button",
      tabindex:0,"aria-label":base.name+"; independent starbase",
      "aria-pressed":selected?"true":"false",style:"cursor:pointer"})
    if(selected)add(group,"circle",{cx:x,cy:y,r:21,fill:"none",
      stroke:"#baff8a","stroke-width":1.4,"stroke-dasharray":"4 4"})
    const points=arr=>arr.map(([dx,dy])=>[x+dx,y+dy].join(",")).join(" ")
    add(group,"polygon",{points:points([[-9,-5],[0,-18],[9,-5]]),
      fill:"#43ec5c",stroke:"#baffca","stroke-width":0.9})
    add(group,"polygon",{points:points([[-9,5],[0,18],[9,5]]),
      fill:"#208f39",stroke:"#aaffb1","stroke-width":0.9})
    add(group,"rect",{x:x-10,y:y-5,width:20,height:10,rx:1,
      fill:"#06462a",stroke:"#7dff9d","stroke-width":1.4})
    add(group,"rect",{x:x-4,y:y-3,width:8,height:6,
      fill:"#041d12",stroke:"#a4ffa7","stroke-width":0.9})
    add(group,"text",{x:x+16,y:y-17,fill:selected?"#dcffb8":"#99edaf",
      "font-family":"monospace","font-size":13,"paint-order":"stroke",
      stroke:"#04101f","stroke-width":4},base.name.toUpperCase())
  }
}

function renderBody(svg,body,selectedId){
  const selected=body.id===selectedId
  const group=add(svg,"g",{
    "data-body-id":body.id,tabindex:0,role:"button",
    "aria-label":body.name+"; "+solarClass(body.kind),
    "aria-pressed":selected?"true":"false",
    style:"cursor:pointer",
  })
  if(selected) add(group,"circle",{
    cx:body.x,cy:body.y,r:body.size+9,
    fill:"none",stroke:"#8cf5ff","stroke-width":2,
    "stroke-dasharray":"4 4",
  })
  if(body.kind==="star"){
    add(group,"circle",{cx:body.x,cy:body.y,r:26,fill:"#ffc85c",opacity:0.13})
  }
  add(group,"circle",{
    cx:body.x,cy:body.y,r:Math.max(6,body.size),
    fill:body.color,stroke:selected?"#fff6d2":"#cde9ef",
    "stroke-width":selected?2:0.7,
  })
  if(body.id==="saturn"){
    add(group,"ellipse",{cx:body.x,cy:body.y,rx:21,ry:7,
      fill:"none",stroke:"#e4cf9d","stroke-width":2.2,
      transform:`rotate(-24 ${body.x} ${body.y})`})
  }
  const right=body.x<630
  const x=body.x+(right?1:-1)*(body.size+10)
  const y=body.y-7
  add(group,"text",{
    x,y,fill:selected?"#bbffff":"#d2e2ed",
    "text-anchor":right?"start":"end",
    "font-family":"monospace","font-size":selected?17:15,
    "font-weight":selected?"bold":"normal",
    "paint-order":"stroke",stroke:"#04101f","stroke-width":4,
  },body.name)
  return group
}

export function drawSolarAtlas(svg,{focus="system",selectedId="earth",navigation=null,
  waypoint=null,selectedStarbaseId=null}={}){
  if(!svg)return
  const layer=svg.querySelector("#nav-solar-content")
  if(!layer)return
  layer.replaceChildren()
  const layout=solarLayout(focus)
  renderOrbits(layer,layout,focus)
  renderVoyage(layer,layout,navigation,focus)
  if(waypoint && !selectedStarbaseId)renderWaypoint(layer,waypoint,focus)
  renderStarbases(layer,navigation?.starbases,focus,selectedStarbaseId)
  // Orbit draw order first, then active bodies/labels above orbit lines.
  for(const body of layout)renderBody(layer,body,selectedId)
}

export function renderSolarDetails(root,selectedId){
  const body=findSolarBody(selectedId)||SOLAR_BODIES[0]
  const info=solarBodySummary(body)
  const name=root.querySelector("#nav-solar-name")
  const type=root.querySelector("#nav-solar-type")
  const distance=root.querySelector("#nav-solar-distance")
  const period=root.querySelector("#nav-solar-period")
  if(name)name.textContent=info.heading
  if(type)type.textContent=info.classification
  if(distance)distance.textContent=info.distance
  if(period)period.textContent=info.period

  const list=root.querySelector("#nav-system-bodies")
  if(!list)return
  list.replaceChildren()
  for(const item of SOLAR_BODIES){
    const button=document.createElement("button")
    button.type="button"
    button.className="solar-body-button"
    button.dataset.bodyId=item.id
    button.setAttribute("aria-pressed",String(item.id===body.id))
    const dot=document.createElement("span")
    dot.className="solar-body-swatch"
    dot.style.backgroundColor=item.color
    dot.setAttribute("aria-hidden","true")
    const label=document.createElement("span")
    label.textContent=item.name
    button.append(dot,label)
    list.appendChild(button)
  }
}
