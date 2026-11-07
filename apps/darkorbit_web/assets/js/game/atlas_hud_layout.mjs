const STORAGE_KEY="space-nova-atlas-hud-v1"
const EDGE=8
const HEADER=64
const FOOTER=46

const clamp=(n,min,max)=>Math.max(min,Math.min(max,n))

export function clampHudPosition(x,y,viewportWidth,viewportHeight,panelWidth,panelHeight) {
  const right=Math.max(EDGE,viewportWidth-panelWidth-EDGE)
  const bottom=Math.max(HEADER,viewportHeight-panelHeight-FOOTER)
  return {
    left:clamp(Math.round(x),EDGE,right),
    top:clamp(Math.round(y),HEADER,bottom),
  }
}

// Positions are purely client preferences; server navigation never reads them.
export function setupAtlasHudDrag({root,panel,grip,reset,storage=globalThis.localStorage}={}) {
  if(!root||!panel||!grip)return
  let drag=null

  const moveTo=(x,y)=>{
    const bounds=root.getBoundingClientRect()
    const panelBounds=panel.getBoundingClientRect()
    const position=clampHudPosition(x,y,bounds.width,bounds.height,
      panelBounds.width,panelBounds.height)
    panel.style.left=position.left+"px"
    panel.style.top=position.top+"px"
    panel.style.right="auto"
    panel.style.bottom="auto"
    return position
  }
  const save=()=>{
    if(!panel.style.left)return
    try{storage?.setItem(STORAGE_KEY,JSON.stringify({
      x:parseFloat(panel.style.left),y:parseFloat(panel.style.top),
    }))}catch{ /* Private browsing may prevent storage; movement still works. */ }
  }
  try{
    const value=JSON.parse(storage?.getItem(STORAGE_KEY)||"null")
    if(Number.isFinite(value?.x)&&Number.isFinite(value?.y))moveTo(value.x,value.y)
  }catch{ /* Ignore invalid persisted preferences. */ }
  grip.addEventListener("pointerdown",event=>{
    if(event.button!==0)return
    const box=panel.getBoundingClientRect()
    drag={offsetX:event.clientX-box.left,offsetY:event.clientY-box.top,
      pointerId:event.pointerId}
    grip.setPointerCapture?.(event.pointerId)
    grip.classList.add("is-dragging")
    event.preventDefault()
  })
  grip.addEventListener("pointermove",event=>{
    if(!drag||event.pointerId!==drag.pointerId)return
    const rect=root.getBoundingClientRect()
    moveTo(event.clientX-rect.left-drag.offsetX,
      event.clientY-rect.top-drag.offsetY)
  })
  const finish=event=>{
    if(!drag||event.pointerId!==drag.pointerId)return
    drag=null
    grip.classList.remove("is-dragging")
    if(grip.hasPointerCapture?.(event.pointerId))grip.releasePointerCapture(event.pointerId)
    save()
  }
  grip.addEventListener("pointerup",finish)
  grip.addEventListener("pointercancel",finish)
  grip.addEventListener("keydown",event=>{
    const direction={ArrowLeft:[-1,0],ArrowRight:[1,0],ArrowUp:[0,-1],ArrowDown:[0,1]}[event.key]
    if(!direction)return
    event.preventDefault()
    const rect=root.getBoundingClientRect(),bounds=panel.getBoundingClientRect()
    const step=event.shiftKey?40:10
    moveTo(bounds.left-rect.left+direction[0]*step,
      bounds.top-rect.top+direction[1]*step)
    save()
  })
  reset?.addEventListener("click",()=>{
    panel.style.left=""
    panel.style.top=""
    panel.style.right=""
    panel.style.bottom=""
    try{storage?.removeItem(STORAGE_KEY)}catch{}
  })
  globalThis.addEventListener?.("resize",()=>{
    if(panel.style.left)moveTo(parseFloat(panel.style.left),parseFloat(panel.style.top))
  })
}
