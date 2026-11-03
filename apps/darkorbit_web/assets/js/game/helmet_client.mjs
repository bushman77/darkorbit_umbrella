import {Socket} from "phoenix"
import {StereoSpaceView} from "./stereo_view.js"

const STORAGE_KEY = "darkorbit:pilot_hmd_credential"
const key = value => String(value)

// Display-only companion. Never joins WorldChannel or sends flight commands.
export class HelmetClient {
  constructor(root) {
    this.root = root
    this.canvas = root.querySelector("#helmet-viewport")
    this.messageNode = root.querySelector("#helmet-message")
    this.pairCode = root.dataset.pairCode || null
    this.credential = localStorage.getItem(STORAGE_KEY)
    this.mode = "standby"
    this.entities = new Map()
    this.selfId = null
    this.selectedTargetId = null
    this.beams = []
    this.lastLaserFeedback = null
    this.view = null
    this.running = false
    this.frameCount = 0
  }

  start() {
    const fullscreen = this.root.querySelector("#helmet-fullscreen")
    fullscreen?.addEventListener("click", async () => {
      try { await document.documentElement.requestFullscreen() } catch (_error) { /* optional */ }
      try { await screen.orientation?.lock?.("landscape") } catch (_error) { /* optional */ }
      fullscreen.hidden = true
    })

    if (!this.pairCode && !this.credential) {
      this.message("Open the Pilot HMD panel in your laptop's Atlas and scan its QR code.")
      return
    }

    this.socket = new Socket("/socket", {
      params: () => this.pairCode ?
        {pair_code: this.pairCode} : {helmet_token: this.credential},
    })
    this.socket.connect()
    this.channel = this.socket.channel("helmet:viewer", {device_name: "Android VR headset"})
    this.channel.on("helmet_mode", ({mode}) => this.setMode(mode))
    this.channel.on("helmet_snapshot", ({map, player_id}) => {
      this.selfId = key(player_id)
      this.applyWorld(map)
    })
    this.channel.on("world_state", map => {
      if (this.mode === "combat") this.applyWorld(map)
    })
    this.channel.on("helmet_revoked", () => {
      localStorage.removeItem(STORAGE_KEY)
      this.credential = null
      this.mode = "standby"
      this.stop()
      this.message("Helmet was unpaired. Scan a new QR code.")
      this.socket.disconnect()
    })
    this.channel.on("helmet_error", ({reason}) => this.message(reason))
    this.channel.onError(() => {
      this.stop()
      this.message("Helmet link interrupted. Reconnecting…")
    })
    this.channel.join()
      .receive("ok", ({mode, player_id, credential}) => {
        if (credential) {
          this.credential = credential
          localStorage.setItem(STORAGE_KEY, credential)
          this.pairCode = null
          window.history.replaceState({}, "", "/helmet")
        }
        this.selfId = key(player_id)
        this.setMode(mode)
      })
      .receive("error", ({reason}) => this.message("Helmet join rejected: " + (reason || "unknown")))
    window.addEventListener("resize", () => this.resize())
    document.addEventListener("visibilitychange", () => {
      if (document.hidden) {
        this.running = false
        this.report(false)
      } else if (this.mode === "combat") {
        this.startRendering()
      }
    })
    setInterval(() => this.report(this.running && this.frameCount > 0 && !document.hidden), 5000)
  }

  setMode(mode) {
    this.mode = mode === "combat" ? "combat" : "standby"
    if (this.mode === "combat") {
      this.startRendering()
    } else {
      this.stop()
      this.message("")
    }
  }

  startRendering() {
    if (document.hidden || this.running) return
    if (!this.view) {
      try {
        this.view = new StereoSpaceView(this.canvas)
        this.view.setMode("sbs")
      } catch (_error) {
        this.message("This phone's browser could not initialize WebGL.")
        this.report(false)
        return
      }
    }
    this.canvas.hidden = false
    this.resize()
    this.message("")
    this.running = true
    requestAnimationFrame(time => this.frame(time))
  }

  stop() {
    this.running = false
    this.frameCount = 0
    this.canvas.hidden = true
    this.entities.clear()
    this.beams = []
    this.report(false)
  }

  resize() {
    if (!this.view) return
    this.view.resize(window.innerWidth, window.innerHeight, Math.min(window.devicePixelRatio || 1, 1.5))
  }

  applyWorld(map) {
    if (!map?.entities || this.mode !== "combat") return
    const active = new Set()
    for (const e of map.entities) {
      const id = key(e.id)
      active.add(id)
      const pos = e.position_3d || e.position || {x: 0, y: 0, z: 0}
      const dest = e.destination_3d || e.destination
      this.entities.set(id, {
        id,
        kind: e.kind,
        npcTypeId: e.npc_type_id,
        displayName: e.display_name,
        status: e.status,
        render: {...pos, z: pos.z || 0},
        destination: dest,
        angle: e.angle || 0,
        attitude: e.attitude,
        orientation: e.orientation,
        velocity: e.velocity,
        throttle: e.throttle,
        flightMode: e.flight_mode,
        targetId: e.target_id == null ? null : key(e.target_id),
        hull: e.hull,
        maxHull: e.max_hull,
        shields: e.shields,
        maxShields: e.max_shields,
        attackRange: e.attack_range,
        angularVelocity: e.angular_velocity,
      })
    }
    for (const id of this.entities.keys()) {
      if (!active.has(id)) this.entities.delete(id)
    }
    this.selectedTargetId = this.entities.get(this.selfId)?.targetId || null
  }

  frame(time) {
    if (!this.running || this.mode !== "combat" || document.hidden) return
    try {
      this.view.render(this, time)
      this.frameCount++
      if (this.frameCount === 1) this.report(true)
    } catch (_error) {
      this.stop()
      this.message("Headset rendering stopped. Check WebGL support.")
      return
    }
    requestAnimationFrame(next => this.frame(next))
  }

  report(rendering) {
    if (this.channel?.state === "joined") {
      this.channel.push("rendering_status", {rendering: Boolean(rendering)})
    }
  }

  message(value) {
    if (!this.messageNode) return
    this.messageNode.textContent = value || ""
    this.messageNode.hidden = !value
  }
}

export function startHelmetClient() {
  const root = document.getElementById("helmet-client")
  if (root) new HelmetClient(root).start()
}
