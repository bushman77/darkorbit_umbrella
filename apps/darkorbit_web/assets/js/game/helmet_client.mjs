import {Socket} from "phoenix"
import {StereoSpaceView} from "./stereo_view.js"
import {visualLaserRays} from "./laser_burst.mjs"
import {laserFeedback} from "./laser_feedback.mjs"

const STORAGE_KEY = "darkorbit:pilot_hmd_credential"
const GAP_KEY = "darkorbit:pilot_hmd_eye_gap"
const EYE_SEP_KEY = "darkorbit:pilot_hmd_eye_sep"
const key = value => String(value)

// Display-only companion. Never joins WorldChannel or sends flight commands.
export class HelmetClient {
  constructor(root) {
    this.root = root
    this.canvas = root.querySelector("#helmet-viewport")
    this.messageNode = root.querySelector("#helmet-message")
    this.pairCode = root.dataset.pairCode || null
    this.credential = localStorage.getItem(STORAGE_KEY)
    // A remembered helmet must win over an old one-time QR invitation.
    // Otherwise scanning the QR again repeatedly attempts a consumed code.
    if (this.credential && this.pairCode) {
      this.pairCode = null
      window.history.replaceState({}, "", "/helmet")
    }
    this.mode = "standby"
    this.immersiveReady = false
    this.windowed = false
    this.eyeGapPx = Math.max(0, Math.min(80, Number(localStorage.getItem(GAP_KEY)) || 0))
    this.eyeSepMm = Math.max(40, Math.min(85, Number(localStorage.getItem(EYE_SEP_KEY)) || 64))
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
    this.setupImmersiveControls()

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
    this.channel.on("laser_fired", shot => this.laserFired(shot))
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
    this.socket.onError(() => this.message("Socket unavailable. Check the phone's network connection or headset registration."))
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
      .receive("error", ({reason}) => {
        // Do not endlessly retry a spent QR invitation. Fresh pairing must
        // begin from the laptop's open Atlas HMD panel.
        const hint = reason === "invalid_pairing" ?
          "QR invitation already used or no longer open. If paired, open /helmet on this phone; otherwise rescan a new Atlas QR." :
          "Helmet join rejected: " + (reason || "unknown")
        this.message(hint)
        this.channel.leave()
      })
    window.addEventListener("resize", () => {
      this.resize()
      if (this.mode === "combat" && this.immersiveReady && !this.running) this.startRendering()
    })
    window.addEventListener("orientationchange", () => this.resize())
    window.visualViewport?.addEventListener("resize", () => this.resize())
    document.addEventListener("visibilitychange", () => {
      if (document.hidden) {
        this.running = false
        this.report(false)
      } else if (this.mode === "combat" && this.immersiveReady) {
        this.startRendering()
      }
    })
    setInterval(() => this.report(this.running && this.frameCount > 0 && !document.hidden), 5000)
  }

  setupImmersiveControls() {
    const setup = this.root.querySelector("#helmet-setup")
    const hint = this.root.querySelector("#helmet-fullscreen-hint")
    const fullscreen = this.root.querySelector("#helmet-fullscreen")
    const windowed = this.root.querySelector("#helmet-windowed")
    const gap = this.root.querySelector("#helmet-eye-gap")
    const sep = this.root.querySelector("#helmet-eye-sep")

    if (gap) gap.value = String(this.eyeGapPx)
    if (sep) sep.value = String(this.eyeSepMm)
    this.updateAlignmentLabels()

    gap?.addEventListener("input", () => {
      this.eyeGapPx = Math.max(0, Math.min(80, Number(gap.value) || 0))
      localStorage.setItem(GAP_KEY, String(this.eyeGapPx))
      this.applyAlignment()
    })
    sep?.addEventListener("input", () => {
      this.eyeSepMm = Math.max(40, Math.min(85, Number(sep.value) || 64))
      localStorage.setItem(EYE_SEP_KEY, String(this.eyeSepMm))
      this.applyAlignment()
    })

    fullscreen?.addEventListener("click", async () => {
      if (!this.root.requestFullscreen) {
        if (hint) hint.textContent = "Fullscreen is unavailable in this browser. Try Chrome or Samsung Internet, or continue windowed."
        return
      }
      try {
        // Must execute within the direct tap: mobile browsers do not grant
        // fullscreen automatically when a QR navigation loads the page.
        await this.root.requestFullscreen()
        this.windowed = false
        this.immersiveReady = true
        if (setup) setup.hidden = true
        try { await screen.orientation?.lock?.("landscape") } catch (_error) { /* rotate manually */ }
        this.resize()
        if (this.mode === "combat") this.startRendering()
      } catch (_error) {
        if (hint) hint.textContent = "Fullscreen was blocked. Open in Chrome/Samsung Internet, or use Continue without fullscreen."
      }
    })
    windowed?.addEventListener("click", () => {
      this.windowed = true
      this.immersiveReady = true
      if (setup) setup.hidden = true
      if (this.mode === "combat") this.startRendering()
    })
    document.addEventListener("fullscreenchange", () => {
      this.resize()
      if (document.fullscreenElement === this.root) {
        this.immersiveReady = true
        if (setup) setup.hidden = true
        if (this.mode === "combat") this.startRendering()
      } else if (!this.windowed && this.immersiveReady) {
        this.immersiveReady = false
        this.stop()
        if (setup) setup.hidden = false
      }
    })
  }

  updateAlignmentLabels() {
    const gap = this.root.querySelector("#helmet-eye-gap-value")
    const sep = this.root.querySelector("#helmet-eye-sep-value")
    if (gap) gap.textContent = this.eyeGapPx + "px"
    if (sep) sep.textContent = this.eyeSepMm + "mm"
  }

  applyAlignment() {
    this.updateAlignmentLabels()
    this.view?.setHelmetAlignment({eyeGapPx: this.eyeGapPx, eyeSep: this.eyeSepMm / 1000})
  }

  setMode(mode) {
    this.mode = mode === "combat" ? "combat" : "standby"
    if (this.mode === "combat") {
      if (this.immersiveReady) this.startRendering()
    } else {
      this.stop()
      this.message("")
    }
  }

  startRendering() {
    if (document.hidden || this.running || !this.immersiveReady) return
    if (window.innerWidth < window.innerHeight) {
      this.canvas.hidden = true
      this.message("Rotate the phone to landscape for side-by-side headset alignment.")
      this.report(false)
      return
    }
    if (!this.view) {
      try {
        this.view = new StereoSpaceView(this.canvas)
        this.view.setMode("sbs")
        this.applyAlignment()
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

  laserFired(shot) {
    if (this.mode !== "combat") return
    const attacker = this.entities.get(key(shot.attacker_id))
    const target = this.entities.get(key(shot.target_id))
    const at = performance.now()
    for (const ray of visualLaserRays(shot, attacker, target)) {
      this.beams.push({...ray, hostile: attacker?.kind === "npc",
        startedAt: at, expiresAt: at + 550})
    }
    if (key(shot.attacker_id) === this.selfId) {
      this.lastLaserFeedback = laserFeedback(shot, this.entities, at)
    }
  }

  frame(time) {
    if (!this.running || this.mode !== "combat" || document.hidden) return
    try {
      this.beams = this.beams.filter(beam => beam.expiresAt > time)
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
    const setup = this.root.querySelector("#helmet-setup")
    const hint = this.root.querySelector("#helmet-fullscreen-hint")
    if (value && setup && !setup.hidden && hint) hint.textContent = value
  }
}

export function startHelmetClient() {
  const root = document.getElementById("helmet-client")
  if (root) new HelmetClient(root).start()
}
