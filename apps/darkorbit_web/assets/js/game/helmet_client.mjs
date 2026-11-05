import {Socket} from "phoenix"
import {StereoSpaceView} from "./stereo_view.js"
import {visualLaserRays} from "./laser_burst.mjs"
import {laserFeedback} from "./laser_feedback.mjs"
import {helmetSocketParams} from "./helmet_auth.mjs"
import {adjustedHelmetAlignment, HELMET_GAP_MIN, HELMET_GAP_MAX} from "./helmet_alignment.mjs"
import {restoredHelmetCalibration} from "./helmet_calibration_restore.mjs"
import {renderHelmetEncounter} from "./helmet_encounter_view.mjs"
import {helmetPlanetaryNavigation} from "./helmet_planetary_navigation.mjs"
import {HelmetScreenWake} from "./helmet_screen_wake.mjs"

const STORAGE_KEY = "darkorbit:pilot_hmd_credential"
const GAP_KEY = "darkorbit:pilot_hmd_eye_gap"
const EYE_SEP_KEY = "darkorbit:pilot_hmd_eye_sep"
const CALIBRATION_DIRTY_KEY = "darkorbit:pilot_hmd_calibration_unsynced"
const CALIBRATION_SAVE_DELAY_MS = 350
const key = value => String(value)

// Display-only companion. Never joins WorldChannel or sends flight commands.
export class HelmetClient {
  constructor(root) {
    this.root = root
    this.canvas = root.querySelector("#helmet-viewport")
    this.messageNode = root.querySelector("#helmet-message")
    this.encounterNode = root.querySelector("#helmet-encounter")
    this.pairCode = root.dataset.pairCode || null
    this.credential = localStorage.getItem(STORAGE_KEY)
    // Keep the QR invitation until the saved token has been verified.
    // If the local credential was revoked, the new QR can still enroll.
    this.mode = "standby"
    this.immersiveReady = false
    this.windowed = false
    this.eyeGapPx = Math.max(HELMET_GAP_MIN, Math.min(HELMET_GAP_MAX, Number(localStorage.getItem(GAP_KEY) ?? 8)))
    this.eyeSepMm = Math.max(40, Math.min(85, Number(localStorage.getItem(EYE_SEP_KEY)) || 64))
    this.calibrationRevision = 0
    this.calibrationSaveTimer = null
    this.calibrationSaveInFlight = false
    this.entities = new Map()
    this.selfId = null
    this.selectedTargetId = null
    this.beams = []
    this.lastLaserFeedback = null
    this.view = null
    // StereoSpaceView reads the same navComputer.visual data on laptop and HMD.
    this.navComputer = {solarNavigation: {planetary_view: null}}
    this.screenWake = new HelmetScreenWake()
    this.running = false
    this.frameCount = 0
  }

  async start() {
    this.setupImmersiveControls()

    if (this.credential) {
      const verification = await this.verifySavedCredential()
      if (verification === true && this.pairCode) {
        // The phone is already registered. Do not consume a second invitation.
        this.pairCode = null
        window.history.replaceState({}, "", "/helmet")
      }
    }

    if (!this.credential && this.pairCode) {
      // Redeem once over HTTP and persist the token BEFORE opening Phoenix.
      // A viewer channel crash must never leave a consumed QR with no token.
      if (!await this.redeemPairingCode()) return
    }

    if (!this.credential) {
      this.message("No saved helmet registration. Open Atlas → PILOT HMD and scan a new QR code.")
      return
    }

    this.socket = new Socket("/socket", {
      params: () => helmetSocketParams({credential: this.credential}),
    })
    this.socket.connect()
    this.channel = this.socket.channel("helmet:viewer", {device_name: "Android VR headset"})
    this.channel.on("helmet_mode", ({mode}) => this.setMode(mode))
    this.channel.on("helmet_alignment_adjust", ({axis, direction}) => {
      this.adjustAlignmentFromPilot(axis, direction)
    })
    this.channel.on("helmet_snapshot", ({map, player_id}) => {
      this.selfId = key(player_id)
      this.applyWorld(map)
    })
    this.channel.on("world_state", map => {
      if (this.mode === "combat") this.applyWorld(map)
    })
    this.channel.on("laser_fired", shot => this.laserFired(shot))
    this.channel.on("helmet_encounter", payload => {
      renderHelmetEncounter(this.encounterNode, payload)
    })
    this.channel.on("helmet_navigation", payload => {
      this.navComputer.solarNavigation = helmetPlanetaryNavigation(payload)
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
      this.calibrationSaveInFlight = false
      this.stop()
      this.message("Helmet link interrupted. Reconnecting…")
    })
    this.socket.onError(async () => {
      // A rejected WebSocket transport doesn't expose a Phoenix channel
      // reason. Check the bearer credential separately so a stale pairing
      // isn't misreported as an unreachable LAN.
      if (this.credential && await this.verifySavedCredential() === false) {
        this.socket.disconnect()
        this.stop()
        this.message("Saved helmet pairing rejected by Phoenix. Open Atlas → PILOT HMD → Forget headset, then scan a fresh QR code.")
      } else {
        this.message("Helmet WebSocket interrupted or blocked. Check that the laptop is still serving on the phone's network.")
      }
    })
    this.channel.join()
      .receive("ok", ({mode, player_id, calibration}) => {
        this.selfId = key(player_id)
        // Restore BEFORE starting the SBS frame loop; never flash a default
        // separation in the headset when PostgreSQL already has a setting.
        this.restoreServerCalibration(calibration)
        this.setMode(mode)
      })
      .receive("error", ({reason}) => {
        this.message("Helmet viewer connection refused: " + (reason || "unknown"))
        this.channel.leave()
      })
    window.addEventListener("resize", () => {
      this.resize()
      if (this.mode === "combat" && this.immersiveReady && !this.running) this.startRendering()
    })
    window.addEventListener("orientationchange", () => this.resize())
    window.visualViewport?.addEventListener("resize", () => this.resize())
    document.addEventListener("visibilitychange", () => {
      this.screenWake.onVisibilityChange()
      if (document.hidden) {
        // Best-effort write before the OS backgrounds the browser.
        this.persistCalibration()
        this.running = false
        this.report(false)
      } else if (this.mode === "combat" && this.immersiveReady) {
        this.startRendering()
      }
    })
    window.addEventListener("pagehide", () => {
      this.persistCalibration()
      this.screenWake.disable()
    })
    window.addEventListener("pageshow", () => {
      if (this.immersiveReady) this.screenWake.enable()
    })
    setInterval(() => {
      this.report(this.running && this.frameCount > 0 && !document.hidden)
      if (localStorage.getItem(CALIBRATION_DIRTY_KEY) === "1" &&
          !this.calibrationSaveTimer && !this.calibrationSaveInFlight) {
        this.scheduleCalibrationSave()
      }
    }, 5000)
  }

  async redeemPairingCode() {
    if (!this.pairCode) return false

    // Check storage before consuming the single-use invitation.
    try {
      const storageTestKey = STORAGE_KEY + ":storage_test"
      localStorage.setItem(storageTestKey, "1")
      localStorage.removeItem(storageTestKey)
    } catch (_error) {
      this.message("This browser is blocking local storage. Enable site storage or use Chrome/Samsung Internet before pairing.")
      return false
    }

    this.message("Registering helmet with Phoenix…")
    try {
      const response = await fetch("/helmet/pair", {
        method: "POST",
        headers: {"Content-Type": "application/json", "Accept": "application/json"},
        cache: "no-store",
        credentials: "omit",
        body: JSON.stringify({code: this.pairCode, device_name: "Galaxy S21 headset"}),
      })
      const result = await response.json().catch(() => ({}))
      if (response.ok && typeof result.credential === "string") {
        // Save the credential before any viewer channel can subscribe/crash.
        localStorage.setItem(STORAGE_KEY, result.credential)
        this.credential = result.credential
        this.pairCode = null
        window.history.replaceState({}, "", "/helmet")
        this.message("Helmet registered. Connecting display…")
        return true
      }
      if (response.status === 409) {
        this.message("The laptop already has a paired helmet, but this browser has no valid saved credential. Choose Forget headset in the laptop Atlas, then scan the new QR once.")
      } else if (response.status === 410) {
        this.message("This QR invitation was already consumed or the Atlas panel closed. If the laptop shows PAIRED but this phone has no saved credential, choose Forget headset once, then scan a fresh QR with the panel open.")
      } else {
        this.message("Helmet registration failed (" + response.status + "). Check the Phoenix server log.")
      }
      return false
    } catch (_error) {
      this.message("Could not reach the helmet registration endpoint. Check the laptop network address.")
      return false
    }
  }

  async verifySavedCredential() {
    if (!this.credential) return null
    try {
      const response = await fetch("/helmet/verify", {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "Authorization": "Bearer " + this.credential,
        },
        cache: "no-store",
        credentials: "omit",
      })
      if (response.status === 401) {
        // Local bearer is stale or revoked. The phone can re-enroll with
        // a newly scanned QR, or tell the pilot how to regenerate pairing.
        localStorage.removeItem(STORAGE_KEY)
        this.credential = null
        this.message("Saved helmet registration is not recognized. In the laptop Atlas, choose Forget headset, then scan its new QR code.")
        return false
      }
      return response.ok ? true : null
    } catch (_error) {
      // Could be a temporary LAN failure: do not destroy a valid credential.
      return null
    }
  }

  setupImmersiveControls() {
    const setup = this.root.querySelector("#helmet-setup")
    const hint = this.root.querySelector("#helmet-fullscreen-hint")
    const fullscreen = this.root.querySelector("#helmet-fullscreen")
    const windowed = this.root.querySelector("#helmet-windowed")
    fullscreen?.addEventListener("click", async () => {
      if (!this.root.requestFullscreen) {
        if (hint) hint.textContent = "Fullscreen is unavailable in this browser. Try Chrome or Samsung Internet, or continue windowed."
        return
      }
      try {
        // Request wake lock within the same explicit tap as fullscreen. The
        // browser may reject it on insecure LAN HTTP or low battery.
        this.screenWake.enable()
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
        this.screenWake.disable()
        if (hint) hint.textContent = "Fullscreen was blocked. Open in Chrome/Samsung Internet, or use Continue without fullscreen."
      }
    })
    windowed?.addEventListener("click", () => {
      this.screenWake.enable()
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
        this.screenWake.disable()
        this.immersiveReady = false
        this.stop()
        if (setup) setup.hidden = false
      }
    })
  }

  adjustAlignmentFromPilot(axis, direction) {
    if (this.mode !== "combat" || !this.immersiveReady || !this.running) return
    const next = adjustedHelmetAlignment(
      {eyeGapPx: this.eyeGapPx, eyeSepMm: this.eyeSepMm}, axis, direction)
    if (!next) return

    this.eyeGapPx = next.eyeGapPx
    this.eyeSepMm = next.eyeSepMm
    this.rememberCalibration()

    this.applyAlignment()
    this.reportAlignment()
  }

  restoreServerCalibration(saved) {
    const remote = saved && {
      eyeGapPx: saved.eye_gap_px,
      eyeSepMm: saved.eye_sep_mm,
    }
    const restored = restoredHelmetCalibration({
      server: remote,
      local: {eyeGapPx: this.eyeGapPx, eyeSepMm: this.eyeSepMm},
      dirty: localStorage.getItem(CALIBRATION_DIRTY_KEY) === "1",
    })

    this.eyeGapPx = restored.calibration.eyeGapPx
    this.eyeSepMm = restored.calibration.eyeSepMm
    localStorage.setItem(GAP_KEY, String(this.eyeGapPx))
    localStorage.setItem(EYE_SEP_KEY, String(this.eyeSepMm))

    if (restored.needsSave) {
      localStorage.setItem(CALIBRATION_DIRTY_KEY, "1")
      this.calibrationRevision++
      this.scheduleCalibrationSave()
    } else {
      localStorage.removeItem(CALIBRATION_DIRTY_KEY)
    }

    this.applyAlignment()
    this.reportAlignment()
  }

  rememberCalibration() {
    // Local storage updates synchronously on every keypress. A reload before
    // PostgreSQL acknowledges still preserves the last adjustment on the phone.
    localStorage.setItem(GAP_KEY, String(this.eyeGapPx))
    localStorage.setItem(EYE_SEP_KEY, String(this.eyeSepMm))
    localStorage.setItem(CALIBRATION_DIRTY_KEY, "1")
    this.calibrationRevision++
    this.scheduleCalibrationSave()
  }

  scheduleCalibrationSave() {
    if (this.calibrationSaveTimer) clearTimeout(this.calibrationSaveTimer)
    this.calibrationSaveTimer = setTimeout(() => {
      this.calibrationSaveTimer = null
      this.persistCalibration()
    }, CALIBRATION_SAVE_DELAY_MS)
  }

  persistCalibration() {
    if (this.calibrationSaveInFlight || this.channel?.state !== "joined" ||
        localStorage.getItem(CALIBRATION_DIRTY_KEY) !== "1") return

    this.calibrationSaveInFlight = true
    const revision = this.calibrationRevision
    const payload = {
      eye_gap_px: Math.round(this.eyeGapPx),
      eye_sep_mm: Math.round(this.eyeSepMm),
    }

    this.channel.push("save_alignment", payload, 5000)
      .receive("ok", saved => {
        this.calibrationSaveInFlight = false
        if (revision === this.calibrationRevision &&
            saved.eye_gap_px === payload.eye_gap_px &&
            saved.eye_sep_mm === payload.eye_sep_mm) {
          localStorage.removeItem(CALIBRATION_DIRTY_KEY)
        } else {
          // A newer adjustment was made during this write: save it next.
          this.scheduleCalibrationSave()
        }
      })
      .receive("error", () => {
        // Retain local data. Retry after the channel reconnects or the
        // periodic health report fires; never interrupt the VR display.
        this.calibrationSaveInFlight = false
      })
      .receive("timeout", () => {
        this.calibrationSaveInFlight = false
      })
  }

  reportAlignment() {
    if (this.channel?.state !== "joined") return
    this.channel.push("alignment_state", {
      eye_gap_px: Math.round(this.eyeGapPx),
      eye_sep_mm: Math.round(this.eyeSepMm),
    })
  }

  applyAlignment() {
    this.view?.setHelmetAlignment({eyeGapPx: this.eyeGapPx, eyeSep: this.eyeSepMm / 1000})
  }

  setMode(mode) {
    this.mode = mode === "combat" ? "combat" : "standby"
    if (this.mode !== "combat") renderHelmetEncounter(this.encounterNode, null)
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
    renderHelmetEncounter(this.encounterNode, null)
    this.canvas.hidden = true
    this.entities.clear()
    this.navComputer.solarNavigation = {planetary_view: null}
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
        shipClass: e.ship_class || null,
        course: e.course || null,
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
