import {
  MAX_WAYPOINTS, chartProjection, chartWorldPoint,
  appendWaypoint, routeDistance, parseCoordinates,
} from "./navigation_math.mjs"
import {findSolarBody, SOLAR_FOCUSES} from "./solar_system.mjs"
import {drawSolarAtlas, renderSolarDetails} from "./solar_atlas.mjs"
import {solarMenuTarget,canNavigateSolar} from "./solar_context_menu.mjs"
import {setupAtlasHudDrag} from "./atlas_hud_layout.mjs"

const NS = "http://www.w3.org/2000/svg"
const number = value => Math.round(value).toLocaleString("en-US")
const coordText = point => point ?
  `${number(point.x)} / ${number(point.y)} / Z ${number(point.z ?? 0)}` : "— / — / Z —"

function element(name, attributes = {}, label = null) {
  const node = document.createElementNS(NS, name)
  for (const [attribute, value] of Object.entries(attributes)) node.setAttribute(attribute, String(value))
  if (label != null) node.textContent = String(label)
  return node
}

function drawLink(group, projection, from, to, color, dashed = false) {
  const a = projection.point(from)
  const b = projection.point(to)
  group.appendChild(element("line", {
    x1: a.x, y1: a.y, x2: b.x, y2: b.y,
    stroke: color, "stroke-width": 2.3,
    "stroke-dasharray": dashed ? "8 7" : "none",
    opacity: 0.9,
  }))
}

export class NavigationComputer {
  constructor({root, getEntities, getSelfId, getBoundaries, isConnected, engage, halt,
    solarSetCourse = (_id, done) => done(false, null, "unavailable"),
    solarCancelCourse = done => done(false, null, "unavailable"),
    solarHail = (_id, done) => done(false, null, "unavailable"),
    solarEnterFreeFlight = done => done(false, null, "unavailable"),
    solarResumeCruise = done => done(false, null, "unavailable"),
    onOpen, onClose}) {
    this.root = root
    this.getEntities = getEntities
    this.getSelfId = getSelfId
    this.getBoundaries = getBoundaries
    this.isConnected = isConnected
    this.engage = engage
    this.halt = halt
    this.solarSetCourse = solarSetCourse
    this.solarCancelCourse = solarCancelCourse
    this.solarHail = solarHail
    this.solarEnterFreeFlight = solarEnterFreeFlight
    this.solarResumeCruise = solarResumeCruise
    this.onOpen = onOpen
    this.onClose = onClose
    this.draft = []
    this.isOpen = false
    this.pending = false
    // The first Atlas screen is SOL. Local tactical route planning stays
    // completely separate from AU coordinates and cannot receive a planet
    // marker as a server waypoint.
    this.view = "system"
    this.solarFocus = "system"
    this.solarSelection = "earth"
    this.solarNavigation = null
    this.solarPending = false
    this.solarStatusMessage = "Connecting to the system navigation computer…"
    this.lastDrawAt = -Infinity
  }

  start() {
    this.solarSvg = this.root.querySelector("#nav-solar-chart")
    setupAtlasHudDrag({
      root:this.root,
      panel:this.root.querySelector(".atlas-hud-right"),
      grip:this.root.querySelector("#nav-hud-drag"),
      reset:this.root.querySelector("#nav-hud-reset"),
    })
    this.solarMenu = this.root.querySelector("#nav-solar-context-menu")
    this.solarContextBodyId = null
    this.solarSvg?.addEventListener("contextmenu", event => {
      event.preventDefault()
      const clicked=event.target?.closest?.("[data-body-id]")?.getAttribute("data-body-id")
      this.openSolarContextMenu(clicked,event.clientX,event.clientY)
    })
    this.solarSvg?.addEventListener("keydown",event => {
      if(event.key!=="ContextMenu" && !(event.key==="F10"&&event.shiftKey))return
      event.preventDefault()
      const rect=this.solarSvg.getBoundingClientRect()
      const clicked=event.target?.closest?.("[data-body-id]")?.getAttribute("data-body-id")
      this.openSolarContextMenu(clicked,rect.left+rect.width/2,rect.top+rect.height/2)
    })
    this.solarMenu?.addEventListener("click",event => {
      const action=event.target?.closest?.("[data-solar-action]")?.dataset.solarAction
      const id=this.solarContextBodyId
      if(!action || !id)return
      this.closeSolarContextMenu()
      this.selectSolarBody(id)
      if(action==="analyze"){
        const detail=this.root.querySelector("#nav-solar-analysis")
        if(detail)detail.open=true
      }else if(action==="navigate" &&
        canNavigateSolar(id,this.solarNavigation,this.isConnected(),this.solarPending)){
        this.engageSolarCourse()
      }
    })
    this.root.addEventListener?.("pointerdown",event=>{
      if(!event.target?.closest?.("#nav-solar-context-menu,#nav-solar-chart")){
        this.closeSolarContextMenu()
      }
    })
    this.root.querySelector("#nav-target-dismiss")?.addEventListener("click",() => {
      const panel=this.root.querySelector("#nav-target-panel")
      if(panel)panel.hidden=true
    })
    this.root.querySelector("#nav-solar-engage")?.addEventListener("click",
      () => this.engageSolarCourse())
    this.root.querySelector("#nav-solar-cancel")?.addEventListener("click",
      () => this.cancelSolarCourse())
    this.root.querySelector("#nav-traffic-contacts")?.addEventListener("click", event => {
      const id = event.target?.closest?.("[data-traffic-hail]")?.dataset.trafficHail
      if (id) this.hailTraffic(id)
    })
    this.root.querySelector("#nav-view-system")?.addEventListener("click",
      () => this.setView("system"))
    this.root.querySelector("#nav-view-sector")?.addEventListener("click",
      () => this.setView("sector"))
    this.root.querySelector("#nav-solar-chart")?.addEventListener("click", event => {
      this.closeSolarContextMenu()
      const id = event.target?.closest?.("[data-body-id]")?.getAttribute("data-body-id")
      if(id)this.selectSolarBody(id)
    })
    this.solarSvg?.addEventListener("keydown", event => {
      if(!["Enter"," "].includes(event.key))return
      const id=event.target?.closest?.("[data-body-id]")?.getAttribute("data-body-id")
      if(!id)return
      event.preventDefault()
      this.selectSolarBody(id)
    })
    this.root.querySelector("#nav-system-bodies")?.addEventListener("click",event=>{
      const id=event.target?.closest?.("[data-body-id]")?.dataset.bodyId
      if(id)this.selectSolarBody(id)
    })
    for(const button of this.root.querySelectorAll("[data-solar-focus]")){
      button.addEventListener("click",()=>this.setSolarFocus(button.dataset.solarFocus))
    }
    this.svg = this.root.querySelector("#nav-chart")
    this.chartLayer = this.root.querySelector("#nav-chart-content")
    this.root.querySelector("#nav-close")?.addEventListener("click", () => this.close())
    this.root.querySelector("#nav-clear")?.addEventListener("click", () => {
      this.draft = []
      this.note("Draft cleared. Active server course unchanged.")
      this.draw(0, true)
    })
    this.root.querySelector("#nav-undo")?.addEventListener("click", () => {
      this.draft.pop()
      this.note("Last draft waypoint removed.")
      this.draw(0, true)
    })
    this.root.querySelector("#nav-engage")?.addEventListener("click", () => this.submit())
    this.root.querySelector("#nav-stop")?.addEventListener("click", () => this.stop())
    this.root.querySelector("#nav-coordinate-form")?.addEventListener("submit", event => {
      event.preventDefault()
      const x = this.root.querySelector("#nav-x").value
      const y = this.root.querySelector("#nav-y").value
      const z = this.root.querySelector("#nav-z").value
      const point = parseCoordinates(x, y, this.getBoundaries(), z)
      this.addWaypoint(point)
    })
    this.svg.addEventListener("click", event => {
      const matrix = this.svg.getScreenCTM()
      if (!matrix) return
      const pointer = this.svg.createSVGPoint()
      pointer.x = event.clientX
      pointer.y = event.clientY
      const local = pointer.matrixTransform(matrix.inverse())
      const xy = chartWorldPoint({x: local.x, y: local.y}, this.getBoundaries())
      const altitude = this.root.querySelector("#nav-z").value
      if (altitude.trim() === "") {
        this.note("Enter a waypoint altitude before selecting a position.")
        return
      }
      const z = Number(altitude)
      this.addWaypoint(xy && {...xy, z})
    })
    return this
  }

  ownShip() {
    return this.getEntities().get(this.getSelfId())
  }

  setRegion(name, mapId) {
    // This is a server-provided local tactical region, not a new SOL route.
    this.regionName = name || "Sector 1-1"
    this.regionMapId = mapId || "1-1"
    this.draft = []
    const regionTab = this.root.querySelector("#nav-view-sector")
    if (regionTab) regionTab.textContent = this.regionName
    const caption = this.root.querySelector("#nav-sector-view .nav-map-caption span")
    if (caption) caption.textContent = this.regionName.toUpperCase() + " // XY PROJECTION"
    const bounds = this.getBoundaries()
    for (const [id, min, max] of [
      ["#nav-x", 0, bounds.width],
      ["#nav-y", 0, bounds.height],
      ["#nav-z", bounds.altitude_min ?? -3000, bounds.altitude_max ?? 3000],
    ]) {
      const input = this.root.querySelector(id)
      if (input) {
        input.min = String(min)
        input.max = String(max)
      }
    }
    this.setView(this.view)
  }

  setView(view) {
    if(view!=="system"&&view!=="sector")return
    this.closeSolarContextMenu()
    this.view=view
    const system=view==="system"
    this.root.querySelector("#nav-solar-view").hidden=!system
    this.root.querySelector("#nav-sector-view").hidden=system
    this.root.querySelector("#nav-view-system").setAttribute("aria-selected",String(system))
    this.root.querySelector("#nav-view-sector").setAttribute("aria-selected",String(!system))
    this.root.querySelector("#nav-view-system").classList.toggle("is-active",system)
    this.root.querySelector("#nav-view-sector").classList.toggle("is-active",!system)
    this.root.querySelector("#nav-title").textContent=system?
      "Solar System Atlas":(this.regionName || "Sector 1-1") + " Navigation"
    this.root.querySelector("#nav-subtitle").textContent=system?
      "One star system · Sun, eight planets and Pluto · select a world to inspect" :
      "Local XY tactical chart · plot waypoints with independent Z altitude"
    if(this.isOpen)this.draw(0,true)
  }

  setSolarFocus(focus) {
    if(!SOLAR_FOCUSES.includes(focus))return
    this.solarFocus=focus
    // A selected outer planet is still in the data panel, but not on the
    // magnified inner display. Keep focus consistent with visible markers.
    if(focus==="inner"&&findSolarBody(this.solarSelection)?.au>1.524){
      this.solarSelection="earth"
    }
    for(const button of this.root.querySelectorAll("[data-solar-focus]")){
      const current=button.dataset.solarFocus===focus
      button.classList.toggle("is-active",current)
      button.setAttribute("aria-pressed",String(current))
    }
    if(this.isOpen&&this.view==="system")this.draw(0,true)
  }

  openSolarContextMenu(clickedId,clientX,clientY) {
    if(!this.isOpen || this.view!=="system" || !this.solarMenu || !this.solarSvg)return
    const id=solarMenuTarget(clickedId,this.solarSelection)
    if(!id)return
    this.solarContextBodyId=id
    const target=this.root.querySelector("#nav-solar-context-target")
    if(target)target.textContent="TARGET / "+findSolarBody(id).name.toUpperCase()+
      (findSolarBody(clickedId)?"":" (SELECTED)")
    const navigate=this.solarMenu.querySelector('[data-solar-action="navigate"]')
    if(navigate)navigate.disabled=!canNavigateSolar(id,this.solarNavigation,this.isConnected(),this.solarPending)
    this.solarMenu.hidden=false
    const rect=this.solarMenu.parentElement?.getBoundingClientRect()
    if(!rect)return
    const width=this.solarMenu.offsetWidth||210
    const height=this.solarMenu.offsetHeight||110
    const left=Math.max(8,Math.min(clientX-rect.left,rect.width-width-8))
    const top=Math.max(8,Math.min(clientY-rect.top,rect.height-height-8))
    this.solarMenu.style.left=left+"px"
    this.solarMenu.style.top=top+"px"
  }

  closeSolarContextMenu() {
    if(this.solarMenu)this.solarMenu.hidden=true
    this.solarContextBodyId=null
  }

  selectSolarBody(id) {
    if(!findSolarBody(id))return
    this.solarSelection=id
    // Selection is deliberate: reveal the compact overlay, never a sidebar.
    const targetPanel=this.root.querySelector("#nav-target-panel")
    if(targetPanel)targetPanel.hidden=false
    if(this.solarFocus==="inner"&&findSolarBody(id).au>1.524){
      this.setSolarFocus("system")
    }
    if(this.isOpen&&this.view==="system")this.draw(0,true)
  }

  setSolarNavigation(navigation) {
    if(navigation?.system_id!=="sol" || !["idle","traveling"].includes(navigation.status))return
    this.solarNavigation=navigation
    this.solarStatusMessage=navigation.pending_encounter ?
      "ENCOUNTER HOLD · DECISION REQUIRED" :
      navigation.free_flight ? "MANUAL FLIGHT · CRUISE PAUSED" :
      navigation.status==="traveling" ?
        "SUBLIGHT INTERPLANETARY CRUISE · AI OBSTACLE AVOIDANCE" : "CONVENTIONAL FLIGHT READY"
    if(this.isOpen&&this.view==="system")this.renderSolarView()
  }

  engageSolarCourse() {
    const navigation=this.solarNavigation
    if(!canNavigateSolar(this.solarSelection,navigation,this.isConnected(),this.solarPending))return
    const destination=this.solarSelection
    this.solarPending=true
    this.solarStatusMessage="Submitting course to the SOL helm…"
    this.renderSolarNavigation()
    this.solarSetCourse(destination,(ok,updated,reason)=>{
      this.solarPending=false
      this.solarStatusMessage=ok?
        "Course accepted. En route.": `Course rejected: ${reason || "unavailable"}`
      if(ok&&updated)this.solarNavigation=updated
      if(this.isOpen&&this.view==="system")this.renderSolarView()
    })
  }

  cancelSolarCourse() {
    if(this.solarPending || !this.isConnected() || this.solarNavigation?.status!=="traveling")return
    this.solarPending=true
    this.solarStatusMessage="Requesting transit abort…"
    this.renderSolarNavigation()
    this.solarCancelCourse((ok,updated,reason)=>{
      this.solarPending=false
      this.solarStatusMessage=ok?
        "Transit aborted. Remaining at departure region." :
        `Abort rejected: ${reason || "unavailable"}`
      if(ok&&updated)this.solarNavigation=updated
      if(this.isOpen&&this.view==="system")this.renderSolarView()
    })
  }

  hailTraffic(id) {
    if (!this.isConnected()) return
    const status = this.root.querySelector("#nav-traffic-comms")
    if (status) status.textContent = "Opening civilian frequency…"
    this.solarHail(id, (ok, communication, reason) => {
      if (!status) return
      if (!ok) {
        status.textContent = `Hail unavailable: ${reason || "contact lost"}`
        return
      }
      const manifest = Object.entries(communication.cargo || {})
        .map(([item, count]) => `${item.replaceAll("_", " ")}: ${count}`)
        .join(", ")
      status.textContent = `${communication.call_sign}: ${communication.message}\nCargo: ${manifest}`
    })
  }

  renderTrafficContacts() {
    const root = this.root.querySelector("#nav-traffic-contacts")
    if (!root) return
    const contacts = this.solarNavigation?.contacts || []
    root.replaceChildren()
    if (!contacts.length) {
      root.textContent = "No vessels currently in sensor range."
      return
    }
    for (const contact of contacts) {
      const item = document.createElement("div")
      const flyby = this.solarNavigation?.encounter?.contact_id === contact.id
      item.className = flyby
        ? "rounded border border-emerald-300/70 bg-emerald-950/40 p-2"
        : "rounded border border-cyan-500/25 bg-slate-900/80 p-2"
      const title = document.createElement("p")
      title.className = "font-semibold text-cyan-100"
      title.textContent = `${flyby ? "CLOSE PASS · " : ""}${contact.call_sign} · ${contact.disposition.toUpperCase()}`
      const detail = document.createElement("p")
      detail.className = "mt-1 text-slate-300"
      detail.textContent = `${contact.origin_id} → ${contact.destination_id} · ${contact.state.replaceAll("_", " ")} · ${Math.round(contact.distance_km).toLocaleString("en-US")} game km`
      const button = document.createElement("button")
      button.type = "button"
      button.className = "nav-button mt-2"
      button.dataset.trafficHail = contact.id
      button.textContent = "Hail vessel"
      item.append(title, detail, button)
      root.appendChild(item)
    }
  }

  renderSolarNavigation() {
    const nav=this.solarNavigation
    const name=id=>findSolarBody(id)?.name || "Unknown"
    const traveling=nav?.status==="traveling"
    const connected=this.isConnected()
    const status=this.root.querySelector("#nav-solar-state")
    if(status)status.textContent=!connected?"WAITING FOR RELAY":this.solarStatusMessage
    const location=this.root.querySelector("#nav-solar-location")
    if(location)location.textContent=nav?name(nav.location_id):"—"
    const route=this.root.querySelector("#nav-solar-route")
    if(route)route.textContent=traveling?
      `${name(nav.origin_id)} → ${name(nav.destination_id)}`:"NO ACTIVE TRANSIT"
    const progress=this.root.querySelector("#nav-solar-progress")
    const percent=Math.max(0,Math.min(100,Math.round((nav?.progress || 0)*100)))
    if(progress)progress.value=percent
    const percentLabel=this.root.querySelector("#nav-solar-progress-label")
    const duration=ms=>{
      const seconds=Math.max(0,Math.ceil((ms || 0)/1000))
      const minutes=Math.floor(seconds/60)
      return `${minutes}:${String(seconds%60).padStart(2,"0")}`
    }
    if(percentLabel)percentLabel.textContent=traveling?
      `${percent}% · ${duration(nav.remaining_ms)} remaining`:
      "Conventional flight · choose a planet to begin sublight cruise"
    const drive=this.root.querySelector("#nav-solar-drive")
    if(drive)drive.textContent=nav?.cruise_paused ? "ENCOUNTER HOLD · CRUISE PAUSED" :
      traveling ? "SUBLIGHT INTERPLANETARY CRUISE" : "CONVENTIONAL"
    const speed=this.root.querySelector("#nav-solar-speed")
    if(speed)speed.textContent=nav?.cruise_paused ? "0 game km/s · held at encounter" :
      traveling ? `${Math.round(nav.cruise_speed_km_s || 0).toLocaleString("en-US")} game km/s` :
      "Conventional thrusters"
    const distance=this.root.querySelector("#nav-solar-distance-travelled")
    if(distance)distance.textContent=traveling ?
      `${Math.round(nav.distance_travelled_km || 0).toLocaleString("en-US")} / ${Math.round(nav.travel_distance_km || 0).toLocaleString("en-US")} game km` :
      "No interplanetary course"
    const eta=this.root.querySelector("#nav-solar-eta")
    if(eta)eta.textContent=traveling ? duration(nav.remaining_ms) : "—"
    const button=this.root.querySelector("#nav-solar-engage")
    if(button){
      button.disabled=!canNavigateSolar(this.solarSelection,nav,connected,this.solarPending)
      button.textContent=traveling?"Transit in progress":
        `Set course to ${name(this.solarSelection)}`
    }
    const abort=this.root.querySelector("#nav-solar-cancel")
    if(abort)abort.disabled=this.solarPending||!connected||!traveling||Boolean(nav?.pending_encounter)
    this.renderTrafficContacts()
  }

  renderSolarView() {
    drawSolarAtlas(this.solarSvg,{
      focus:this.solarFocus,selectedId:this.solarSelection,
      navigation:this.solarNavigation,
    })
    renderSolarDetails(this.root,this.solarSelection)
    this.renderSolarNavigation()
  }

  open() {
    if (this.isOpen || this.solarPending) return
    if (this.solarNavigation?.status === "traveling" &&
        this.solarNavigation?.free_flight &&
        !this.solarNavigation?.tactical_encounter) {
      this.solarPending = true
      this.solarResumeCruise((ok, navigation, reason) => {
        this.solarPending = false
        if (!ok) {
          this.solarStatusMessage = "AI drive unavailable: " + (reason || "relay error")
          return
        }
        if (navigation) this.solarNavigation = navigation
        this.openNow()
      })
      return
    }
    this.openNow()
  }

  openNow() {
    if (this.isOpen) return
    this.isOpen = true
    this.root.hidden = false
    const altitude = this.root.querySelector("#nav-z")
    const bounds = this.getBoundaries()
    altitude.min = String(bounds.altitude_min ?? -3000)
    altitude.max = String(bounds.altitude_max ?? 3000)
    // Default to current altitude for a new chart session, but permit changes.
    if (!this.draft.length) altitude.value = String(this.ownShip()?.target?.z ?? 0)
    this.onOpen?.()
    this.setView(this.view)
    if(this.view==="sector"){
      this.note("Click the sector chart to plot waypoints. Engage to hand the course to the helm.")
    }
    this.root.querySelector("#nav-close")?.focus()
  }

  close() {
    if (!this.isOpen || this.solarPending) return
    if (this.solarNavigation?.status === "traveling" &&
        !this.solarNavigation?.free_flight &&
        !this.solarNavigation?.tactical_encounter) {
      if (this.solarNavigation?.pending_encounter) {
        this.solarStatusMessage = "Resolve the current encounter before free flight."
        return
      }
      this.solarPending = true
      this.solarEnterFreeFlight((ok, navigation, reason) => {
        this.solarPending = false
        if (!ok) {
          this.solarStatusMessage = "Manual flight unavailable: " + (reason || "relay error")
          if (this.isOpen && this.view === "system" && this.solarSvg) this.renderSolarNavigation()
          return
        }
        if (navigation) this.solarNavigation = navigation
        this.closeNow()
      })
      return
    }
    this.closeNow()
  }

  closeNow() {
    if (!this.isOpen) return
    this.closeSolarContextMenu()
    this.isOpen = false
    this.root.hidden = true
    this.onClose?.()
  }

  handleKey(event) {
    if (event.defaultPrevented || event.repeat) return false
    if (this.isOpen && event.code === "Escape") {
      event.preventDefault()
      if(this.solarMenu && !this.solarMenu.hidden)this.closeSolarContextMenu()
      else this.close()
      return true
    }
    // Tab and Shift+Tab remain inside the modal navigation computer.
    if (this.isOpen && event.code === "Tab" && !event.altKey && !event.ctrlKey && !event.metaKey) {
      const focusable = [...this.root.querySelectorAll("button:not(:disabled), input:not(:disabled)")].filter(node => !node.hidden)
      const first = focusable[0]
      const last = focusable.at(-1)
      if ((event.shiftKey && document.activeElement === first) ||
          (!event.shiftKey && document.activeElement === last)) {
        event.preventDefault()
        ;(event.shiftKey ? last : first)?.focus()
        return true
      }
    }
    if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return false
    const tag = event.target?.tagName
    const editing = event.target?.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(tag)
    if (event.code === "KeyM" && !editing) {
      event.preventDefault()
      this.isOpen ? this.close() : this.open()
      return true
    }
    return false
  }

  addWaypoint(point) {
    const updated = appendWaypoint(this.draft, point, this.getBoundaries())
    if (updated === this.draft) {
      this.note(`Waypoint rejected — select a position within the sector, up to ${MAX_WAYPOINTS} legs.`)
      return
    }
    this.draft = updated
    this.note(`Waypoint ${this.draft.length} plotted. Engage autopilot when ready.`)
    this.draw(0, true)
  }

  submit() {
    if (this.pending || !this.isConnected() || !this.draft.length ||
        this.solarNavigation?.status==="traveling") return
    this.pending = true
    this.refreshStatus()
    const waypoints = this.draft.map(({x, y, z}) => ({x, y, z: z ?? 0}))
    this.engage(waypoints, (ok, reason) => {
      this.pending = false
      if (ok) {
        this.draft = []
        this.note("Course accepted by authoritative helm. Ship en route.")
      } else {
        this.note(`Course rejected: ${reason || "network unavailable"}`)
      }
      this.draw(0, true)
    })
  }

  stop() {
    if (this.pending || !this.isConnected() ||
        this.solarNavigation?.status==="traveling") return
    this.pending = true
    this.refreshStatus()
    this.halt((ok, reason) => {
      this.pending = false
      this.note(ok ? "Helm stopped by server. Route cancelled." : `Stop failed: ${reason || "network unavailable"}`)
      this.draw(0, true)
    })
  }

  note(message) {
    this.root.querySelector("#nav-message").textContent = message
  }

  refreshStatus() {
    const self = this.ownShip()
    const running = self?.navigationMode === "autopilot" && Boolean(self?.destination)
    const legs = (self?.routeWaypoints?.length || 0) + (self?.destination ? 1 : 0)
    const connected = this.isConnected()
    this.root.querySelector("#nav-state").textContent =
      !connected ? "DISCONNECTED" : running ? `AUTOPILOT ACTIVE · ${legs} leg(s) left` :
      self?.destination ? "MANUAL STEERING" : "HELM IDLE"
    this.root.querySelector("#nav-position").textContent = coordText(self?.target)
    const preview = this.draft.length ? this.draft : (running ? [self.destination, ...self.routeWaypoints] : [])
    this.root.querySelector("#nav-distance").textContent = `${number(routeDistance(self?.target, preview))} units`
    this.root.querySelector("#nav-engage").disabled = this.pending || !connected || !this.draft.length
    this.root.querySelector("#nav-stop").disabled = this.pending || !connected || !self?.destination
    this.root.querySelector("#nav-undo").disabled = this.pending || !this.draft.length
    this.root.querySelector("#nav-clear").disabled = this.pending || !this.draft.length
    const list = this.root.querySelector("#nav-waypoints")
    list.replaceChildren()
    const routeList = this.draft.length ? this.draft :
      running ? [self.destination, ...self.routeWaypoints] : []
    for (const [index, waypoint] of routeList.entries()) {
      const item = document.createElement("li")
      const prefix = this.draft.length ? "WP" : "ACTIVE"
      item.textContent = `${prefix} ${index + 1}   ${coordText(waypoint)}`
      list.appendChild(item)
    }
    this.root.querySelector("#nav-waypoint-count").textContent =
      this.draft.length ? `${this.draft.length} / ${MAX_WAYPOINTS} DRAFT` :
      running ? `${routeList.length} ACTIVE` : `0 / ${MAX_WAYPOINTS}`
  }

  draw(time, force = false) {
    if (!this.isOpen || (!force && time - this.lastDrawAt < 100)) return
    this.lastDrawAt = time
    if(this.view==="system"){
      // No fake realtime planet positions; render only on explicit selection,
      // zoom or view changes. The live sector chart keeps refreshing normally.
      if(force)this.renderSolarView()
      return
    }
    this.refreshStatus()
    const projection = chartProjection(this.getBoundaries())
    if (!projection) return
    const layer = this.chartLayer
    layer.replaceChildren()
    layer.appendChild(element("rect", {
      x: projection.x, y: projection.y, width: projection.width, height: projection.height,
      fill: "rgba(5,31,52,.48)", stroke: "#3a8da7", "stroke-width": 1.6,
    }))
    const bounds = this.getBoundaries()
    for (let x = 2000; x < bounds.width; x += 2000) {
      const p = projection.point({x, y: 0})
      layer.appendChild(element("line", {x1: p.x, y1: projection.y, x2: p.x,
        y2: projection.y + projection.height, stroke: "#21516d", opacity: 0.55}))
    }
    for (let y = 2000; y < bounds.height; y += 2000) {
      const p = projection.point({x: 0, y})
      layer.appendChild(element("line", {x1: projection.x, y1: p.y,
        x2: projection.x + projection.width, y2: p.y, stroke: "#21516d", opacity: 0.55}))
    }
    const own = this.ownShip()
    const active = own?.navigationMode === "autopilot" && own.destination
      ? [own.destination, ...(own.routeWaypoints || [])] : []
    const waypoints = this.draft.length ? this.draft : active
    const routeColor = this.draft.length ? "#73edf7" : "#fac17e"
    if (own?.render && waypoints.length) {
      let previous = own.render
      for (const [index, point] of waypoints.entries()) {
        drawLink(layer, projection, previous, point, routeColor, true)
        const pos = projection.point(point)
        layer.appendChild(element("circle", {cx: pos.x, cy: pos.y, r: 10,
          fill: "#09263b", stroke: routeColor, "stroke-width": 1.8}))
        layer.appendChild(element("text", {x: pos.x, y: pos.y + 3.5,
          fill: routeColor, "font-size": 10, "text-anchor": "middle",
          "font-family": "monospace"}, String(index + 1)))
        previous = point
      }
    }
    for (const entity of this.getEntities().values()) {
      if (entity.status === "destroyed" || !entity.render) continue
      const p = projection.point(entity.render)
      const ownEntity = entity.id === this.getSelfId()
      const hex = ownEntity ? "#6ff5ff" : entity.kind === "npc" ? "#ffad76" : "#c6b0ff"
      layer.appendChild(element("circle", {cx: p.x, cy: p.y, r: ownEntity ? 6 : 4,
        fill: hex, opacity: 0.93}))
      if (ownEntity) {
        layer.appendChild(element("circle", {cx: p.x, cy: p.y, r: 11,
          fill: "none", stroke: hex, "stroke-width": 1.5}))
      }
    }
  }
}
