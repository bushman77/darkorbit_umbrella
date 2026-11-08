import {Socket} from "phoenix"
import {
  applyAuthoritativeDamage,
  entityKey,
  healthPercent,
  nearestNpc,
} from "./combat_client.mjs"
import {
  combatKeyIntent,
  gameplayTypingTarget,
  manualLaserPointerIntent,
  desiredEntityAngle,
  hotbarActionActive,
  smoothAngle,
} from "./combat_controls.mjs"
import {CockpitWindowManager} from "./cockpit_window_manager.mjs"
import {MinimapRenderer} from "./minimap_renderer.mjs"
import {PointerNavigation} from "./pointer_navigation.mjs"
import {StereoSpaceView} from "./stereo_view.js"
import {HelmetControl} from "./helmet_control.mjs"
import {HelmetAlignmentKeyGate} from "./helmet_alignment_keys.mjs"
import {NavigationComputer} from "./navigation_computer.mjs"
import {FlightControls} from "./flight_controls.mjs"
import {WorldStreamDelta} from "./world_stream_delta.mjs"
import {gameSocketEndpoint} from "./socket_endpoint.mjs"
import {
  MouseSteering, validMouseSensitivity, MOUSE_STEERING_IDLE_MS,
} from "./mouse_steering.mjs"
import {smoothAttitude} from "./attitude_interpolation.mjs"
import {smoothOrientation, orientationTelemetry} from "./orientation_interpolation.mjs"
import {SpaceLaserTrigger} from "./space_laser_trigger.mjs"
import {applyLaserBurstDamage, visualLaserRays} from "./laser_burst.mjs"
import {laserFeedback, LASER_FEEDBACK_MS} from "./laser_feedback.mjs"
import {nextFlightMode, validFlightMode} from "./display_modes.mjs"
import {cameraSettleSeconds} from "./camera_response.mjs"
import {planetaryImpactMessage} from "./planetary_impact.mjs"
import {
  ownPlanetaryWarning, proximityEventWarning, planetaryWarningView,
} from "./planetary_warning.mjs"
import {ownStationWarning, stationWarningView} from "./station_warning.mjs"
import {validOrbitalMapId, shouldEnterOrbitalRegion} from "./orbital_regions.mjs"
import {tacticalEncounterAction} from "./solar_encounter_actions.mjs"

const clamp = (value, minimum, maximum) => Math.min(Math.max(value, minimum), maximum)
const validDestination = (destination, boundaries) =>
  destination &&
  Number.isFinite(destination.x) &&
  Number.isFinite(destination.y) &&
  destination.x >= 0 &&
  destination.x <= boundaries.width &&
  destination.y >= 0 &&
  destination.y <= boundaries.height
const number = value => new Intl.NumberFormat("en-US", {maximumFractionDigits: 0}).format(value || 0)

class SpaceClient {
  constructor(root) {
    this.root = root
    // Transparent DOM hit surface. Three.js owns the only flight renderer.
    this.canvas = root.querySelector("#space-viewport")
    this.stereoView = null
    this.displayMode = "3d"
    this.mapId = root.dataset.mapId
    this.token = root.dataset.socketToken
    // Per-pilot browser preference, not an authority-bearing network setting.
    this.mouseSteeringKey = "darkorbit:mouse-steering:" + root.dataset.layoutPlayerId
    this.mouseSensitivityKey = "darkorbit:mouse-sensitivity:" + root.dataset.layoutPlayerId
    this.mouseSteeringEnabled = localStorage.getItem(this.mouseSteeringKey) === "1"
    const savedSensitivity = Number(localStorage.getItem(this.mouseSensitivityKey))
    this.mouseSteeringSensitivity = validMouseSensitivity(savedSensitivity)
      ? savedSensitivity : 1
    this.mouseSteering = new MouseSteering({sensitivity: this.mouseSteeringSensitivity})
    this.mouseIdleTimer = null
    this.mouseCaptureLost = false
    this.helmetAlignmentKeys = new HelmetAlignmentKeyGate()
    this.entities = new Map()
    this.pilots = new Map()
    this.boundaries = {width: 20000, height: 12000}
    this.volume = {altitude_min: -3000, altitude_max: 3000}
    this.selfId = null
    this.planetaryWarningLevel = "clear"
    this.planetaryWarningPlanet = null
    this.stationWarningLevel = "clear"
    this.solarEncounter = null
    this.encounterDisplayedId = null
    this.encounterResolving = false
    this.tacticalRetreating = false
    this.player = null
    this.commandDestination = null
    this.selectedTargetId = null
    this.selectedHotbarSlot = 1
    this.worldTick = 0
    this.tickMs = 100
    this.worldStream = null
    this.worldResyncInFlight = false
    this.beams = []
    this.lastLaserFeedback = null
    this.lastFrame = performance.now()
  }

  inSystemCruise() {
    const navigation = this.navComputer?.solarNavigation
    return navigation?.status === "traveling" && !navigation?.tactical_encounter &&
      !navigation?.free_flight
  }

  start() {
    if (!this.canvas || !this.root.querySelector("#space-viewport-3d")) {
      this.showError("The 3D flight viewport is missing.")
      return
    }

    this.cockpit = new CockpitWindowManager({
      root: this.root.querySelector("#cockpit-interface"),
      playerId: this.root.dataset.layoutPlayerId,
    }).start()
    this.minimap = new MinimapRenderer({
      canvas: this.root.querySelector("#cockpit-minimap-canvas"),
      getEntities: () => this.entities.values(),
      getBoundaries: () => this.boundaries,
      getSelfId: () => this.selfId,
      getDestination: () => this.commandDestination,
    }).start()
    this.flightControls = new FlightControls({
      active: () => !this.navComputer?.isOpen && !this.inSystemCruise() &&
        this.channel?.state === "joined" &&
        this.entities.get(this.selfId)?.status !== "destroyed",
      send: input => this.sendFlightControls(input),
    })
    this.setupMouseSteering()
    window.addEventListener("keydown", event => this.flightControls.keyDown(event))
    window.addEventListener("keyup", event => {
      this.flightControls.keyUp(event)
      this.helmetAlignmentKeys.keyUp(event)
    })
    // Only the cockpit hit canvas owns flight input; menus/Atlas retain
    // ordinary scrolling and right-click behavior.
    this.canvas.addEventListener("wheel", event => this.flightControls.wheel(event),
      {passive: false})
    window.addEventListener("blur", () => {
      this.helmetAlignmentKeys.release()
      this.exitMouseSteering()
      this.flightControls.release()
      this.spaceLaser?.release()
    })
    document.addEventListener("visibilitychange", () => {
      if (document.hidden) {
        this.helmetAlignmentKeys.release()
        this.exitMouseSteering()
        this.flightControls.release()
        this.spaceLaser?.release()
      }
    })
    const encounterPanel = this.root.querySelector("#solar-encounter-panel")
    encounterPanel?.addEventListener("click", event => {
      const choice = event.target?.closest?.("[data-encounter-action]")?.dataset.encounterAction
      const encounter = this.solarEncounter
      if (!choice || !encounter || this.encounterResolving) return

      if (choice === "hail") {
        this.encounterMessage("Opening communications…")
        this.solarHail(encounter.contact_id, (ok, communication, reason) => {
          if (this.solarEncounter?.id !== encounter.id) return
          if (!ok) {
            this.encounterMessage("Hail unavailable: " + (reason || "contact out of range") +
              ". You can still resume your course.")
            return
          }
          const manifest = Object.entries(communication.cargo || {})
            .map(([item, count]) => item.replaceAll("_", " ") + ": " + count)
            .join(", ")
          this.encounterMessage(String(communication.message || "Communications established.") +
            (manifest ? "\nManifest: " + manifest : ""))
        })
      } else if (choice === "engage") {
        this.encounterResolving = true
        this.encounterMessage(encounter.classification === "neutral_flyby"
          ? "Intercepting neutral vessel… Your attack may provoke retaliation."
          : "Entering tactical interception…")
        this.showSolarEncounter()
        this.solarEnterEncounter(encounter.id, (ok, result, reason) => {
          this.encounterResolving = false
          if (ok && result?.navigation) {
            this.applySolarNavigation(result.navigation)
            this.navComputer?.close()
            this.setCombatMessage("Intercept engaged. " +
              (result.enemy?.display_name || "Vessel") +
              " is now in tactical range.")
          } else if (this.solarEncounter?.id === encounter.id) {
            this.encounterMessage("Unable to enter combat: " +
              (reason || "intercept unavailable"))
            this.showSolarEncounter()
          }
        })
      } else if (choice === "continue") {
        this.encounterResolving = true
        this.encounterMessage("Requesting course resumption…")
        this.showSolarEncounter()
        this.solarResolveEncounter(encounter.id, (ok, navigation, reason) => {
          this.encounterResolving = false
          if (ok && navigation) {
            this.applySolarNavigation(navigation)
          } else if (this.solarEncounter?.id === encounter.id) {
            this.encounterMessage("Unable to resume: " + (reason || "relay unavailable"))
            this.showSolarEncounter()
          }
        })
      }
    })
    const tacticalPanel = this.root.querySelector("#solar-tactical-panel")
    tacticalPanel?.addEventListener("click", event => {
      const accept = event.target?.closest?.("[data-solar-tactical-surrender]")
      const seize = event.target?.closest?.("[data-solar-tactical-seize]")
      const retreat = event.target?.closest?.("[data-solar-tactical-retreat]")
      if ((!accept && !seize && !retreat) || this.tacticalRetreating) return
      const tactical = this.navComputer?.solarNavigation?.tactical_encounter
      if (!tactical?.id) return
      this.tacticalRetreating = true
      const message = tacticalPanel.querySelector("[data-solar-tactical-message]")
      if (message) message.textContent = seize
        ? "Seizing permitted cargo under inventory lock…"
        : accept ? "Releasing the surrendered captain…"
        : "Withdrawing from interception…"
      const handler = seize ? this.solarSeizeCargo.bind(this)
        : accept ? this.solarAcceptSurrender.bind(this)
        : this.solarRetreatEncounter.bind(this)
      handler(tactical.id, (ok, navigation, reason, claim) => {
        this.tacticalRetreating = false
        if (ok && navigation) {
          this.applySolarNavigation(navigation)
          this.navComputer?.open()
          const cargo = claim?.cargo || {}
          const contents = Object.entries(cargo)
            .map(([id, count]) => count + "t " + id.replaceAll("_", " "))
            .join(", ")
          this.setCombatMessage(seize
            ? "Cargo seized: " + (contents || "none") +
              " · " + claim.faction_id + " standing " + claim.standing
            : accept ? "Merchant released. SOL voyage resumed."
            : "Interception ended. SOL voyage resumed.")
        } else if (message) {
          message.textContent = "Decision unavailable: " + (reason || "relay error")
        }
        this.showSolarTactical()
      })
      this.showSolarTactical()
    })
    // Modal decisions own keyboard focus. Escape and Atlas toggle cannot
    // dismiss a server-held encounter without a choice.
    window.addEventListener("keydown", event => {
      if (!this.solarEncounter) return
      if (event.key === "Tab") {
        const actions = [...encounterPanel.querySelectorAll(
          '.solar-encounter-eye:first-child [data-encounter-action]')]
          .filter(button => !button.hidden && !button.disabled)
        const index = actions.indexOf(document.activeElement)
        const next = event.shiftKey
          ? actions[(index + actions.length - 1) % actions.length]
          : actions[(index + 1) % actions.length]
        if (next) next.focus({preventScroll: true})
        event.preventDefault()
      } else if (event.key === "Escape" || event.key.toLowerCase() === "m") {
        event.preventDefault()
      }
      event.stopImmediatePropagation()
    }, true)

    this.navComputer = new NavigationComputer({
      root: this.root.querySelector("#navigation-computer"),
      getEntities: () => this.entities,
      getSelfId: () => this.selfId,
      getBoundaries: () => ({...this.boundaries, ...this.volume}),
      isConnected: () => this.channel?.state === "joined" && Boolean(this.selfId),
      engage: (waypoints, done) => this.plotCourse(waypoints, done),
      halt: done => this.stopNavigation(done),
      solarSetCourse: (bodyId, done) => this.solarSetCourse(bodyId, done),
      solarCancelCourse: done => this.solarCancelCourse(done),
      solarEnterFreeFlight: done => this.solarEnterFreeFlight(done),
      solarResumeCruise: done => this.solarResumeCruise(done),
      solarHail: (contactId, done) => this.solarHail(contactId, done),
      onOpen: () => {
        this.exitMouseSteering({silent: true})
        this.helmet?.setCombat(false)
        this.navigation?.cancel()
        this.flightControls.release({silent: true})
        this.spaceLaser?.release()
      },
      onClose: () => {
        this.updateMouseSteeringStatus()
        this.helmet?.closePanel()
        this.helmet?.setCombat(true)
        this.canvas.focus({preventScroll: true})
      },
    }).start()
    this.root.querySelector("#nav-open")?.addEventListener("click", () => this.navComputer.open())
    window.addEventListener("keydown", event => this.navComputer.handleKey(event))
    this.root.querySelector("#display-mode")?.addEventListener("change", event => this.setDisplayMode(event.target.value))
    window.addEventListener("keydown", event => this.handleDisplayModeKey(event))
    // Capture before ordinary gameplay handlers or browser reload behavior.
    window.addEventListener("keydown", event => this.handleHelmetAlignmentKey(event), true)
    if (!this.setDisplayMode("3d")) return
    this.canvas.addEventListener("pointerdown", () => this.canvas.focus({preventScroll: true}))
    window.addEventListener("resize", () => this.resize())
    this.navigation = new PointerNavigation({
      canvas: this.canvas,
      destinationForPointer: () => null,
      shipPosition: () => this.entities.get(this.selfId)?.target,
      sendDestination: destination => this.sendDestination(destination),
      // In cockpit mode click selects targets; travel is plotted on the atlas.
      interceptPointerDown: pointer => {
        // While pointer-locked, the mouse coordinates are frozen: left-click
        // targets what the ship is pointing at in the center of the cockpit.
        if (document.pointerLockElement === this.canvas) {
          const rect = this.canvas.getBoundingClientRect()
          this.selectTargetAtPointer({
            clientX: rect.left + rect.width / 2,
            clientY: rect.top + rect.height / 2,
          })
        } else {
          this.selectTargetAtPointer(pointer)
        }
        return true
      },
    }).attach()
    this.canvas.addEventListener("pointerdown", event => this.handleLaserPointerDown(event))
    this.canvas.addEventListener("contextmenu", event => {
      if (!this.navComputer?.isOpen) event.preventDefault()
    })
    this.spaceLaser = new SpaceLaserTrigger({
      active: () => !this.navComputer?.isOpen && !this.inSystemCruise() &&
        this.channel?.state === "joined" &&
        this.entities.get(this.selfId)?.status !== "destroyed",
      worldTick: () => this.worldTick,
      nextAttackTick: () => Number(this.entities.get(this.selfId)?.nextAttackTick) || 0,
      fire: done => this.fireReadyWeapon(done),
    })
    window.addEventListener("pointerup", event => {
      if (event.button === 2) this.spaceLaser.release()
    })
    window.addEventListener("pointercancel", () => this.spaceLaser.release())
    for (const slot of this.root.querySelectorAll("[data-hotbar-slot]")) {
      slot.addEventListener("click", () => this.activateHotbarSlot(Number(slot.dataset.hotbarSlot)))
    }
    window.addEventListener("keydown", event => this.handleCombatKey(event), true)

    // New sessions begin in the SOL system Atlas, not in the combat
    // cockpit. Initialize all flight/weapon input guards first so the
    // Atlas can safely own focus even before the world socket joins.
    // Closing it hands focus back to the existing 3D / SBS cockpit.
    this.navComputer.open()
    this.connect()
    requestAnimationFrame(time => this.frame(time))
  }

  connect() {
    // For native installed builds the game document is local but the
    // authoritative Channel socket lives at the chosen HTTPS server.
    const endpoint = gameSocketEndpoint(this.root.dataset.serverOrigin)
    this.socket = new Socket(endpoint, {params: () => ({token: this.root.dataset.socketToken})})
    this.socket.onOpen(() => this.setConnection("Relay connected", "online"))
    this.socket.onError(() => this.setConnection("Relay interrupted", "error"))
    this.socket.onClose(() => this.setConnection("Relay offline", "error"))
    this.socket.connect()
    this.helmet = new HelmetControl({
      root: this.root,
      socket: this.socket,
      playerId: this.root.dataset.layoutPlayerId,
      combatActive: !this.navComputer.isOpen,
    }).start()

    this.joinSector(this.mapId)
  }

  joinSector(mapId, retry = 0) {
    // Map identity comes from an authenticated region redirect/arrival event,
    // never from browser-provided world coordinates.
    if (!validOrbitalMapId(mapId)) {
      this.showError("Invalid orbital destination map.")
      return
    }

    this.mapId = mapId
    const channel = this.socket.channel(`world:${mapId}`, {stream: "delta_v1"})
    this.channel = channel
    channel.on("world_state", state => {
      if (this.channel !== channel) return
      if (this.worldStream) this.worldStream.reset(state)
      this.applyWorldState(state)
    })
    channel.on("world_delta", delta => {
      if (this.channel !== channel || this.worldResyncInFlight) return
      const map = this.worldStream?.apply(delta)
      if (map) this.applyWorldState(map)
      else this.requestWorldResync()
    })
    channel.on("movement_delta", patch => {
      if (this.channel !== channel || this.worldResyncInFlight) return
      const entity = this.worldStream?.previewEntity(patch)
      if (entity) this.upsertEntity(entity)
    })
    channel.on("solar_navigation_updated", payload => {
      if (String(payload.player_id) === String(this.selfId) && payload.navigation) {
        this.applySolarNavigation(payload.navigation)
      }
    })
    channel.on("world_region_changed", payload => this.switchOrbitalRegion(payload?.map_id))
    // Open the pilot's decision at first contact, without waiting for another
    // navigation tick. The authoritative snapshot also restores it on reconnect.
    channel.on("solar_encounter_started", payload => {
      if (String(payload.player_id) === String(this.selfId) && payload.encounter?.id) {
        this.setSolarEncounter(payload.encounter)
      }
    })
    channel.on("movement_started", entity => this.upsertEntity(entity))
    channel.on("entity_joined", entity => this.entityJoined(entity))
    channel.on("entity_left", entity => this.removeEntity(entity.id))
    channel.on("npc_spawned", entity => this.upsertEntity(entity, true))
    channel.on("npc_movement_started", entity => this.upsertEntity(entity))
    channel.on("npc_state_changed", entity => this.upsertEntity(entity))
    channel.on("target_selected", selection => this.targetSelected(selection))
    channel.on("target_cleared", selection => this.targetCleared(selection))
    channel.on("combat_engaged", engagement => this.combatEngaged(engagement))
    channel.on("combat_disengaged", engagement => this.combatDisengaged(engagement))
    channel.on("laser_fired", attack => this.laserFired(attack))
    channel.on("solar_faction_hit", event => {
      const current = this.navComputer?.solarNavigation?.tactical_encounter?.id
      // A delayed message from the previous encounter cannot be mistaken
      // for an offense against the pilot's newly claimed vessel.
      if (current && event.encounter_id && event.encounter_id !== current) return
      const label = this.root.querySelector("#solar-faction-impact")
      const delta = Number(event.delta)
      const contactName = String(event.call_sign || event.contact_id || "Unknown contact")
      if (label) {
        label.hidden = false
        label.textContent = "FACTION HIT · " + contactName + " · " +
          event.faction_id + " · " + (delta > 0 ? "+" : "") + delta +
          " · STANDING " + event.standing
      }
      this.setCombatMessage("Faction penalty for " + contactName +
        " (" + event.faction_id + "): " + event.delta +
        " · STANDING " + event.standing)
    })
    channel.on("entity_destroyed", destruction => this.entityDestroyed(destruction))
    channel.on("planetary_proximity_changed", event => this.planetaryProximityChanged(event))
    channel.on("station_proximity_changed", event => {
      if (entityKey(event.entity_id) === this.selfId) {
        this.applyStationWarning(event.level === "clear" ? null : event)
      }
    })
    channel.on("station_collision", event => {
      if (entityKey(event.entity_id) === this.selfId) {
        const damage = Number(event.damage?.requested_damage) || 0
        this.setCombatMessage("REFINERY CONTACT · FLIGHT STOPPED · " + damage + " IMPACT DAMAGE")
        if (event.entity) this.upsertEntity(event.entity, true)
      }
    })
    channel.onError(() => {
      if (this.channel === channel) this.setConnection("Sector channel lost", "error")
    })
    channel.onClose(() => {
      if (this.channel === channel && !this.switchingRegion) {
        this.setConnection("Sector channel closed", "error")
      }
    })

    channel.join()
      .receive("ok", response => {
        this.switchingRegion = false
        this.joined(response)
      })
      .receive("error", response => {
        if (this.channel !== channel) return
        if (response.reason === "region_redirect" &&
            response.map_id !== mapId && retry < 2) {
          channel.leave()
          this.joinSector(response.map_id, retry + 1)
          return
        }
        if (response.reason === "already_connected" && this.switchingRegion &&
            retry < 5) {
          // Phoenix may acknowledge leaving before the old session's
          // terminate callback has removed its server-owned registration.
          setTimeout(() => {
            if (this.channel === channel) {
              channel.leave()
              this.joinSector(mapId, retry + 1)
            }
          }, 250)
          return
        }
        this.switchingRegion = false
        const reason = response.reason === "already_connected"
          ? "This pilot already has an active sector connection."
          : `Unable to join sector: ${response.reason || "unknown error"}`
        this.showError(reason)
        this.setConnection("Join rejected", "error")
      })
      .receive("timeout", () => {
        if (this.channel === channel) {
          this.switchingRegion = false
          this.showError("The orbital relay did not answer in time.")
          this.setConnection("Join timeout", "error")
        }
      })
  }

  switchOrbitalRegion(mapId) {
    if (!shouldEnterOrbitalRegion(this.mapId, mapId, this.switchingRegion)) return
    this.switchingRegion = true
    this.setConnection("Entering " + (mapId.startsWith("sol:free_") ?
      "deep-space flight" : mapId + " orbital region"), "online")
    this.exitMouseSteering({silent: true})
    this.flightControls?.release({silent: true})
    this.spaceLaser?.release()
    this.selectedTargetId = null
    this.commandDestination = null
    this.entities.clear()
    this.worldStream = null
    this.worldResyncInFlight = false
    this.beams = []
    this.setSolarEncounter(null)
    this.applyPlanetaryWarning(null, {announce: false})
    this.applyStationWarning(null, {announce: false})
    this.stereoView?.planetaryBody?.dispose()
    const previous = this.channel
    const enter = () => {
      if (this.channel === previous) this.joinSector(mapId)
    }
    previous.leave().receive("ok", enter).receive("timeout", enter)
  }

  joined(response) {
    this.mapId = response.map.map_id
    this.worldStream = response.stream === "delta_v1"
      ? new WorldStreamDelta(response.map) : null
    this.worldResyncInFlight = false
    this.root.dataset.mapId = this.mapId
    this.entities.clear()
    this.player = response.player
    if (Array.isArray(response.hotbar) && this.root.dataset.nativeClient === "true") {
      this.populateNativeHotbar(response.hotbar)
    }
    this.selfId = entityKey(response.player.pilot.id)
    this.boundaries = response.map.boundaries
    this.volume = response.map.volume || this.volume
    this.worldTick = response.map.tick
    this.tickMs = response.map.tick_ms
    this.navComputer?.setRegion(response.map.region_name, response.map.map_id)
    const minimap = this.root.querySelector("#minimap-title")
    if (minimap) minimap.textContent = response.map.region_name || "Sector Minimap"
    this.pilots = new Map(Object.entries(response.pilots || {}))

    if(response.solar_navigation)this.applySolarNavigation(response.solar_navigation)
    for (const entity of response.map.entities) this.upsertEntity(entity, true)
    this.applyPlanetaryWarning(ownPlanetaryWarning(response.map, this.selfId))
    this.applyStationWarning(ownStationWarning(response.map, this.selfId))
    this.syncOwnCombatState()

    this.flightControls.resetThrottle()
    this.flightControls.mode = "cruise"
    this.populateHud()
    this.setConnection("Authoritative sync", "online")
  }

  requestWorldResync() {
    if (this.worldResyncInFlight || this.channel?.state !== "joined") return
    this.worldResyncInFlight = true
    const channel = this.channel
    const failed = () => {
      if (this.channel !== channel) return
      this.worldResyncInFlight = false
      this.setConnection("World resync failed; reconnecting", "error")
      this.socket.disconnect()
      this.socket.connect()
    }
    channel.push("world_resync", {}, 5000)
      .receive("ok", response => {
        if (this.channel !== channel) return
        this.worldResyncInFlight = false
        if (response.map && this.worldStream) {
          this.worldStream.reset(response.map)
          this.applyWorldState(response.map)
        }
      })
      .receive("error", failed)
      .receive("timeout", failed)
  }

  applyWorldState(state) {
    this.orbitalBase = state.orbital_base || null
    this.boundaries = state.boundaries || this.boundaries
    this.volume = state.volume || this.volume
    this.worldTick = state.tick
    this.tickMs = state.tick_ms || this.tickMs
    const activeIds = new Set()

    for (const entity of state.entities) {
      activeIds.add(entityKey(entity.id))
      this.upsertEntity(entity)
    }

    for (const id of this.entities.keys()) {
      if (!activeIds.has(id)) this.removeEntity(id)
    }

    this.applyPlanetaryWarning(ownPlanetaryWarning(state, this.selfId))
    this.applyStationWarning(ownStationWarning(state, this.selfId))
    this.syncOwnCombatState()
    this.updateCombatHud()
    this.showSolarTactical()
  }

  entityJoined(entity) {
    if (entity.pilot) this.pilots.set(entityKey(entity.player_id), entity.pilot)
    this.upsertEntity(entity)
  }

  upsertEntity(entity, snap = false) {
    const id = entityKey(entity.id)
    const existing = this.entities.get(id)
    const p3 = entity.position_3d || entity.position
    const target = {x: p3.x, y: p3.y, z: p3.z ?? 0}
    const d3 = entity.destination_3d || entity.destination
    const destination = d3 ? {x: d3.x, y: d3.y, z: d3.z ?? 0} : null
    const route3d = entity.route_waypoints_3d || entity.route_waypoints || []
    const attitude = entity.attitude || {yaw: 0, pitch: 0, roll: 0}
    const orientation = entity.orientation || null
    const velocity = entity.velocity || {x: 0, y: 0, z: 0}

    if (existing) {
      existing.target = target
      existing.destination = destination
      existing.navigationMode = entity.navigation_mode || "manual"
      existing.routeWaypoints = route3d
      existing.attitude = attitude
      existing.orientation = orientation
      if (orientation && (!existing.renderOrientation || snap)) {
        existing.renderOrientation = {...orientation}
      }
      // Render orientation is independent from server state; never feed the
      // interpolated angles back into the authoritative simulation.
      if (!existing.renderAttitude || snap) existing.renderAttitude = {...attitude}
      existing.angularVelocity = entity.angular_velocity || existing.angularVelocity ||
        {yaw: 0, pitch: 0, roll: 0}
      existing.velocity = velocity
      existing.throttle = entity.throttle ?? 0
      existing.flightMode = entity.flight_mode || "cruise"
      existing.speed = entity.speed
      existing.kind = entity.kind || existing.kind
      existing.playerId = entity.player_id == null ? existing.playerId : entityKey(entity.player_id)
      existing.npcTypeId = entity.npc_type_id || existing.npcTypeId
      existing.shipClass = entity.ship_class || existing.shipClass
      if (Number.isFinite(entity.angle)) existing.angle = entity.angle
      existing.course = entity.course || existing.course
      existing.displayName = entity.display_name || existing.displayName
      existing.hull = entity.hull
      existing.maxHull = entity.max_hull
      existing.shields = entity.shields
      existing.maxShields = entity.max_shields
      existing.shieldAbsorption = entity.shield_absorption
      existing.damage = entity.damage
      existing.attackRange = entity.attack_range
      existing.attackCooldownTicks = entity.attack_cooldown_ticks
      existing.nextAttackTick = entity.next_attack_tick
      existing.targetId = entity.target_id == null ? null : entityKey(entity.target_id)
      existing.engagedTargetId = entity.engaged_target_id == null
        ? null
        : entityKey(entity.engaged_target_id)
      existing.state = entity.state
      existing.status = entity.status
      if (destination) {
        existing.navigationAngle = Math.atan2(
          destination.y - existing.render.y,
          destination.x - existing.render.x
        )
      }
      if (snap) existing.render = {...target}
    } else {
      this.entities.set(id, {
        id,
        kind: entity.kind || "player",
        playerId: entity.player_id == null ? null : entityKey(entity.player_id),
        npcTypeId: entity.npc_type_id,
        shipClass: entity.ship_class || null,
        // Trust the server's actual heading where present. Otherwise use
        // a route-derived initial bearing as a visual-only fallback.
        angle: Number.isFinite(entity.angle) ? entity.angle : destination
          ? Math.atan2(destination.y - target.y, destination.x - target.x)
          : -Math.PI / 2,
        course: entity.course || null,
        displayName: entity.display_name,
        render: {...target},
        target,
        destination,
        navigationMode: entity.navigation_mode || "manual",
        routeWaypoints: route3d,
        attitude,
        renderAttitude: {...attitude},
        orientation,
        renderOrientation: orientation ? {...orientation} : null,
        angularVelocity: entity.angular_velocity || {yaw: 0, pitch: 0, roll: 0},
        velocity,
        throttle: entity.throttle ?? 0,
        flightMode: entity.flight_mode || "cruise",
        speed: entity.speed,
        hull: entity.hull,
        maxHull: entity.max_hull,
        shields: entity.shields,
        maxShields: entity.max_shields,
        shieldAbsorption: entity.shield_absorption,
        damage: entity.damage,
        attackRange: entity.attack_range,
        attackCooldownTicks: entity.attack_cooldown_ticks,
        nextAttackTick: entity.next_attack_tick,
        targetId: entity.target_id == null ? null : entityKey(entity.target_id),
        engagedTargetId: entity.engaged_target_id == null
          ? null
          : entityKey(entity.engaged_target_id),
        state: entity.state,
        status: entity.status,
        navigationAngle: destination
          ? Math.atan2(destination.y - target.y, destination.x - target.x)
          : -Math.PI / 2,
      })
    }

    if (id === this.selfId) {
      this.commandDestination = entity.status !== "destroyed" && validDestination(destination, this.boundaries)
        ? {...destination}
        : null
      this.updateNavigationStatus()
    }
  }

  sendFlightControls(input) {
    if (this.channel?.state !== "joined") return
    this.channel.push("flight_controls", input, 3000)
      .receive("ok", response => {
        if (response.entity) this.upsertEntity(response.entity)
      })
      .receive("error", response => this.showError(`Flight controls rejected: ${response.reason}`))
      .receive("timeout", () => this.showError("Flight control link timed out."))
  }

  applySolarNavigation(navigation) {
    const priorEncounterId = this.navComputer?.solarNavigation?.tactical_encounter?.id
    const nextEncounterId = navigation?.tactical_encounter?.id
    const previouslyTactical = Boolean(priorEncounterId)
    // Each penalty belongs to one strategic contact. Never carry a
    // previous vessel's faction banner into a different tactical fight.
    if (priorEncounterId !== nextEncounterId) {
      const impact = this.root.querySelector("#solar-faction-impact")
      if (impact) {
        impact.hidden = true
        impact.textContent = ""
      }
    }
    this.navComputer.setSolarNavigation(navigation)
    this.setSolarEncounter(navigation?.tactical_encounter
      ? null : navigation?.pending_encounter || null)
    this.showSolarTactical()
    if (previouslyTactical && !navigation?.tactical_encounter &&
        navigation?.status === "traveling") {
      this.setCombatMessage("Interception complete. Original SOL course resumed.")
      this.navComputer?.open()
    }
    const body = navigation?.planetary_view
    const planetaryStatus = this.root.querySelector("#planetary-view-status")
    if (planetaryStatus) {
      const valid = body?.visual_only === true &&
        typeof body.body_id === "string" && Number.isFinite(body.angular_diameter_deg)
      planetaryStatus.hidden = !valid
      if (valid) {
        const approach = body.stage === "approach_preview"
        const detail = approach
          ? `APPROACH · ${body.angular_diameter_deg.toFixed(1)}° APPARENT · PREVIEW`
          : "ORBITAL REGION · REAL-RADIUS VIEW · STAGING PHYSICS"
        planetaryStatus.textContent = `SOL · ${body.body_id.toUpperCase()} · ${detail}`
      }
    }
    const active=this.inSystemCruise()
    this.root.dataset.propulsionMode=active?"interplanetary_cruise":"conventional"
    const label=this.root.querySelector("#propulsion-status")
    if(label)label.textContent=navigation?.free_flight?"DEEP SPACE / MANUAL FLIGHT":
      navigation?.pending_encounter?"ENCOUNTER HOLD / CRUISE PAUSED":
      active?"SUBLIGHT CRUISE / FLIGHT LOCKED":"CONVENTIONAL FLIGHT"
    if(active){
      this.exitMouseSteering({silent: true})
      this.flightControls?.release({silent:true})
      this.spaceLaser?.release()
      this.navigation?.cancel()
    }
  }

  encounterMessage(message) {
    for (const output of this.root.querySelectorAll("[data-encounter-message]")) {
      output.textContent = message
    }
  }

  setSolarEncounter(encounter) {
    const nextId = typeof encounter?.id === "string" ? encounter.id : null
    if (nextId !== this.encounterDisplayedId) {
      this.encounterDisplayedId = nextId
      this.encounterResolving = false
      if (nextId) {
        const description = encounter.classification === "hostile_contact"
          ? "Hostile vessel detected. Your course is on hold until you choose to proceed."
          : encounter.classification === "patrol_attention"
            ? "Faction patrol attention. Decide whether to hail or continue."
            : "Neutral traffic detected. Hail, attack, or ignore. The vessel may retaliate if hit."
        this.encounterMessage(description)
      }
    }
    this.solarEncounter = nextId ? encounter : null
    this.showSolarEncounter()
  }

  showSolarEncounter() {
    const panel = this.root.querySelector("#solar-encounter-panel")
    if (!panel) return
    const wasHidden = panel.hidden
    panel.hidden = !this.solarEncounter
    if (this.navComputer?.root) this.navComputer.root.inert = Boolean(this.solarEncounter)
    if (!this.solarEncounter) {
      if (!wasHidden) {
        const focus = this.navComputer?.isOpen
          ? this.navComputer.root.querySelector("#nav-close")
          : this.canvas
        focus?.focus?.({preventScroll: true})
      }
      return
    }

    const encounter = this.solarEncounter
    const status = encounter.classification === "hostile_contact"
      ? "HOSTILE CONTACT"
      : encounter.classification === "patrol_attention"
        ? "PATROL ATTENTION"
        : "NEUTRAL CONTACT"
    for (const title of panel.querySelectorAll("[data-encounter-title]")) {
      title.textContent = String(encounter.call_sign || "Unidentified vessel") +
        " · " + String(encounter.kind || "vessel").replaceAll("_", " ")
    }
    for (const faction of panel.querySelectorAll("[data-encounter-faction]")) {
      faction.textContent = "FACTION / " +
        String(encounter.faction_name || "Unregistered Organization")
    }
    for (const distance of panel.querySelectorAll("[data-encounter-distance]")) {
      distance.textContent = Math.round(encounter.distance_km || 0).toLocaleString("en-US") +
        " game km at detection · " + status + " · " +
        String(encounter.origin_id || "?") + " → " +
        String(encounter.destination_id || "?")
    }
    const tacticalAction = tacticalEncounterAction(encounter.classification)
    for (const button of panel.querySelectorAll("[data-encounter-action]")) {
      if (button.dataset.encounterAction === "engage") {
        button.hidden = !tacticalAction.visible
        button.textContent = tacticalAction.label
      }
      button.disabled = this.encounterResolving
    }
    if (wasHidden) {
      this.exitMouseSteering({silent: true})
      this.flightControls?.release({silent: true})
      this.spaceLaser?.release()
      panel.querySelector('.solar-encounter-eye:first-child [data-encounter-action="hail"]')
        ?.focus({preventScroll: true})
    }
  }

  showSolarTactical() {
    const panel = this.root.querySelector("#solar-tactical-panel")
    if (!panel) return
    const tactical = this.navComputer?.solarNavigation?.tactical_encounter
    panel.hidden = !tactical
    if (!tactical) {
      this.tacticalRetreating = false
      return
    }
    const label = panel.querySelector("[data-solar-tactical-name]")
    if (label) label.textContent = (tactical.call_sign || "Hostile interception") +
      " · " + (tactical.faction_name || tactical.faction_id || "Unregistered faction")
    const button = panel.querySelector("[data-solar-tactical-retreat]")
    if (button) button.disabled = this.tacticalRetreating

    const surrendered = [...this.entities.values()].some(entity =>
      entity.kind === "npc" &&
      entity.state === "surrendered" &&
      entity.npcTypeId === "solar-scow-" + this.player?.pilot?.id)
    const accept = panel.querySelector("[data-solar-tactical-surrender]")
    const seize = panel.querySelector("[data-solar-tactical-seize]")
    for (const button of [accept, seize]) {
      if (button) {
        button.hidden = !surrendered
        button.disabled = this.tacticalRetreating
      }
    }
    const message = panel.querySelector("[data-solar-tactical-message]")
    if (message && !this.tacticalRetreating) {
      message.textContent = surrendered
        ? "Captain offers surrender. Release them or seize cargo (4-tonne hold limits apply)."
        : "Defeat the opposing vessel, accept surrender if offered, or retreat."
    }
  }

  solarEnterEncounter(encounterId, done) {
    if (this.channel?.state !== "joined") return done(false, null, "relay offline")
    this.channel.push("solar_enter_encounter", {encounter_id: encounterId}, 5000)
      .receive("ok", response => done(true, response))
      .receive("error", response => done(false, null, response.reason))
      .receive("timeout", () => done(false, null, "timeout"))
  }

  solarAcceptSurrender(encounterId, done) {
    if (this.channel?.state !== "joined") return done(false, null, "relay offline")
    this.channel.push("solar_accept_surrender", {encounter_id: encounterId}, 5000)
      .receive("ok", response => done(true, response.navigation))
      .receive("error", response => done(false, null, response.reason))
      .receive("timeout", () => done(false, null, "timeout"))
  }

  solarSeizeCargo(encounterId, done) {
    if (this.channel?.state !== "joined") return done(false, null, "relay offline")
    this.channel.push("solar_seize_cargo", {encounter_id: encounterId}, 5000)
      .receive("ok", response => done(true, response.navigation, null, response.claim))
      .receive("error", response => done(false, null, response.reason))
      .receive("timeout", () => done(false, null, "timeout"))
  }

  solarRetreatEncounter(encounterId, done) {
    if (this.channel?.state !== "joined") return done(false, null, "relay offline")
    this.channel.push("solar_retreat_encounter", {encounter_id: encounterId}, 5000)
      .receive("ok", response => done(true, response.navigation))
      .receive("error", response => done(false, null, response.reason))
      .receive("timeout", () => done(false, null, "timeout"))
  }

  solarSetCourse(target, done) {
    if(this.channel?.state!=="joined")return done(false,null,"relay offline")
    const payload=typeof target==="string" ? {body_id:target} : {point:target}
    this.channel.push("solar_set_course",payload,5000)
      .receive("ok",response=>done(true,response.navigation))
      .receive("error",response=>done(false,null,response.reason))
      .receive("timeout",()=>done(false,null,"timeout"))
  }

  solarEnterFreeFlight(done) {
    if(this.channel?.state!=="joined")return done(false,null,"relay offline")
    this.channel.push("solar_enter_free_flight",{},5000)
      .receive("ok",response=>done(true,response.navigation))
      .receive("error",response=>done(false,null,response.reason))
      .receive("timeout",()=>done(false,null,"timeout"))
  }

  solarResumeCruise(done) {
    if(this.channel?.state!=="joined")return done(false,null,"relay offline")
    this.channel.push("solar_resume_cruise",{},5000)
      .receive("ok",response=>done(true,response.navigation))
      .receive("error",response=>done(false,null,response.reason))
      .receive("timeout",()=>done(false,null,"timeout"))
  }

  solarCancelCourse(done) {
    if(this.channel?.state!=="joined")return done(false,null,"relay offline")
    this.channel.push("solar_cancel_course",{},5000)
      .receive("ok",response=>done(true,response.navigation))
      .receive("error",response=>done(false,null,response.reason))
      .receive("timeout",()=>done(false,null,"timeout"))
  }

  solarResolveEncounter(encounterId, done) {
    if (this.channel?.state !== "joined") return done(false, null, "relay offline")
    this.channel.push("solar_resolve_encounter", {
      encounter_id: encounterId, choice: "continue",
    }, 5000)
      .receive("ok", response => done(true, response.navigation))
      .receive("error", response => done(false, null, response.reason))
      .receive("timeout", () => done(false, null, "timeout"))
  }

  solarHail(contactId, done) {
    if (this.channel?.state !== "joined") return done(false, null, "relay offline")
    this.channel.push("solar_hail", {contact_id: contactId}, 3000)
      .receive("ok", response => done(true, response.communication))
      .receive("error", response => done(false, null, response.reason))
      .receive("timeout", () => done(false, null, "timeout"))
  }

  plotCourse(waypoints, done) {
    if (this.channel?.state !== "joined") return done(false, "relay offline")
    this.channel.push("plot_course", {waypoints}, 5000)
      .receive("ok", response => {
        if (response.entity) this.upsertEntity(response.entity)
        this.flightControls.resetThrottle()
        done(true)
      })
      .receive("error", response => done(false, response.reason))
      .receive("timeout", () => done(false, "timeout"))
  }

  stopNavigation(done) {
    if (this.channel?.state !== "joined") return done(false, "relay offline")
    this.channel.push("stop_navigation", {}, 5000)
      .receive("ok", response => {
        if (response.entity) this.upsertEntity(response.entity)
        done(true)
      })
      .receive("error", response => done(false, response.reason))
      .receive("timeout", () => done(false, "timeout"))
  }

  sendDestination(destination) {
    if (this.inSystemCruise()) return false
    if (!validDestination(destination, this.boundaries)) return false
    if (!this.channel || !this.selfId || this.channel.state !== "joined") {
      this.showError("Navigation is unavailable while the sector relay reconnects.")
      return false
    }

    this.channel
      .push("move", destination, 5000)
      .receive("ok", response => {
        if (response.entity) this.upsertEntity(response.entity)
      })
      .receive("error", response => {
        this.showError(`Navigation rejected: ${response.reason}`)
        this.updateNavigationStatus()
      })
      .receive("timeout", () => this.showError("Navigation command timed out."))

    return true
  }

  handleLaserPointerDown(event) {
    const active = !this.navComputer?.isOpen && !this.inSystemCruise() &&
      this.channel?.state === "joined" &&
      this.entities.get(this.selfId)?.status !== "destroyed"
    if (!manualLaserPointerIntent(event, active)) return

    event.preventDefault()
    this.canvas.focus({preventScroll: true})
    this.spaceLaser?.press()
  }

  selectTargetAtPointer(pointer) {
    if (this.inSystemCruise()) return false
    const rect = this.canvas.getBoundingClientRect()
    const targetId = this.stereoView?.selectNpc(pointer, rect)
    if (!targetId) return false
    this.selectTarget(targetId)
    return true
  }

  handleCombatKey(event) {
    if (this.navComputer?.isOpen) return
    if (this.inSystemCruise()) return
    if (event.defaultPrevented) return
    const intent = combatKeyIntent(event)
    if (!intent) return

    event.preventDefault()
    if (intent.type === "toggle_laser") this.toggleLaserFire()
    if (intent.type === "disengage") this.disengageCombat()
    if (intent.type === "activate_slot") this.activateHotbarSlot(intent.slot)
    if (intent.type === "target_nearest") this.selectNearestTarget()
  }

  selectNearestTarget() {
    const ownShip = this.entities.get(this.selfId)
    const target = nearestNpc(this.entities.values(), ownShip?.target)
    if (target) this.selectTarget(target.id)
    else this.setCombatMessage("No hostile signal in sector telemetry.")
  }

  selectTarget(targetId) {
    if (this.inSystemCruise()) return
    if (!this.channel || !this.selfId) return

    this.channel
      .push("select_target", {target_id: targetId}, 5000)
      .receive("ok", response => this.targetSelected(response.selection))
      .receive("error", response => this.setCombatMessage(`Target rejected: ${response.reason}`))
      .receive("timeout", () => this.setCombatMessage("Targeting command timed out."))
  }

  disengageCombat() {
    if (!this.channel || !this.selfId) return

    this.channel
      .push("disengage_combat", {}, 5000)
      .receive("ok", engagement => {
        this.combatDisengaged(engagement)
        this.targetCleared(engagement)
      })
      .receive("error", response => this.setCombatMessage(`Disengage rejected: ${response.reason}`))
  }

  engageCombat() {
    if (!this.channel || !this.selfId) return
    if (!this.selectedTargetId) {
      this.setCombatMessage("Select an NPC before engaging.")
      return
    }

    this.channel
      .push("engage_combat", {}, 5000)
      .receive("ok", engagement => this.combatEngaged(engagement))
      .receive("error", response => this.setCombatMessage(this.attackError(response.reason)))
      .receive("timeout", () => this.setCombatMessage("Engagement command timed out."))
  }

  fireReadyWeapon(done) {
    if (this.channel?.state !== "joined" || !this.selfId) {
      done(false, "disconnected")
      return
    }

    this.channel
      .push("fire_ready_weapon", {}, 3000)
      .receive("ok", shot => {
        const own = this.entities.get(this.selfId)
        if (own) own.nextAttackTick = shot.next_attack_tick
        this.worldTick = Math.max(this.worldTick, Number(shot.tick) || 0)
        done(true)
      })
      .receive("error", response => {
        this.setCombatMessage(this.attackError(response.reason))
        done(false, response.reason)
      })
      .receive("timeout", () => {
        this.setCombatMessage("Manual laser command timed out.")
        done(false, "timeout")
      })
  }

  toggleLaserFire() {
    if (!this.channel || !this.selfId) return

    this.channel
      .push("toggle_laser_fire", {}, 5000)
      .receive("ok", engagement => this.applyLaserToggle(engagement))
      .receive("error", response => this.setCombatMessage(this.attackError(response.reason)))
      .receive("timeout", () => this.setCombatMessage("Laser toggle timed out."))
  }

  activateHotbarSlot(slot) {
    if (this.inSystemCruise()) return
    if (!this.channel || !this.selfId || !Number.isInteger(slot)) return

    this.selectedHotbarSlot = slot
    this.updateHotbar()
    this.channel
      .push("activate_action", {slot}, 5000)
      .receive("ok", activation => {
        if (activation.status === "empty") {
          this.setCombatMessage(`Action slot ${slot === 10 ? 0 : slot} is empty.`)
        } else if (activation.engagement) this.applyLaserToggle(activation.engagement)
      })
      .receive("error", response => this.setCombatMessage(this.attackError(response.reason)))
      .receive("timeout", () => this.setCombatMessage("Action activation timed out."))
  }

  targetSelected(selection) {
    if (entityKey(selection.player_id) !== this.selfId) return
    this.selectedTargetId = entityKey(selection.target_id)
    const ownShip = this.entities.get(this.selfId)
    if (ownShip) ownShip.targetId = this.selectedTargetId
    this.setCombatMessage("Target lock confirmed.")
    this.updateCombatHud()
  }

  targetCleared(selection) {
    if (entityKey(selection.player_id) !== this.selfId) return
    this.selectedTargetId = null
    const ownShip = this.entities.get(this.selfId)
    if (ownShip) {
      ownShip.targetId = null
      ownShip.engagedTargetId = null
    }
    this.setCombatMessage("Target lock cleared.")
    this.updateCombatHud()
  }

  combatEngaged(engagement) {
    const player = this.entities.get(entityKey(engagement.player_id))
    if (player) player.engagedTargetId = entityKey(engagement.target_id)
    if (entityKey(engagement.player_id) !== this.selfId) return

    this.selectedTargetId = entityKey(engagement.target_id)
    this.selectHotbarAction(engagement.action_id)
    this.setCombatMessage("X1 laser automatic fire engaged.")
    this.updateCombatHud()
  }

  combatDisengaged(engagement) {
    const player = this.entities.get(entityKey(engagement.player_id))
    if (player) player.engagedTargetId = null
    if (entityKey(engagement.player_id) !== this.selfId) return

    this.setCombatMessage(
      engagement.reason === "laser_toggled_off"
        ? "Laser fire stopped. Target lock retained."
        : "Combat disengaged."
    )
    this.updateCombatHud()
  }

  applyLaserToggle(engagement) {
    if (engagement.active) this.combatEngaged(engagement)
    else this.combatDisengaged(engagement)
  }

  selectHotbarAction(actionId) {
    if (!actionId) return

    const slot = [...this.root.querySelectorAll("[data-hotbar-slot]")]
      .find(element => element.dataset.actionId === String(actionId))

    if (slot) this.selectedHotbarSlot = Number(slot.dataset.hotbarSlot)
  }

  syncOwnCombatState() {
    const ownShip = this.entities.get(this.selfId)
    if (!ownShip) return
    this.selectedTargetId = ownShip.targetId
  }

  laserFired(attack) {
    const attacker = this.entities.get(entityKey(attack.attacker_id))
    const target = this.entities.get(entityKey(attack.target_id))
    applyLaserBurstDamage(this.entities, attack)
    if (attacker) attacker.nextAttackTick = attack.next_attack_tick
    this.worldTick = Math.max(this.worldTick, Number(attack.tick) || 0)

    const startedAt = performance.now()
    for (const ray of visualLaserRays(attack, attacker, target)) {
      this.beams.push({
        ...ray,
        hostile: attacker?.kind === "npc",
        shooterId: entityKey(attack.attacker_id),
        startedAt,
        expiresAt: startedAt + 550,
      })
    }

    if (entityKey(attack.attacker_id) === this.selfId) {
      this.lastLaserFeedback = laserFeedback(attack, this.entities, startedAt)
      const feedback = this.lastLaserFeedback
      this.setCombatMessage(feedback.label + "  " + feedback.detail)
    }

    this.updateCombatHud()
  }

  planetaryProximityChanged(event) {
    const warning = proximityEventWarning(event, this.selfId)
    if (warning !== undefined) this.applyPlanetaryWarning(warning)
  }

  applyPlanetaryWarning(warning, {announce = true} = {}) {
    const view = planetaryWarningView(warning)
    this.planetaryWarningDisplay = view
    const nextLevel = view?.level || "clear"
    const nextPlanet = warning?.planet_id || null
    const changed = nextLevel !== this.planetaryWarningLevel ||
      nextPlanet !== this.planetaryWarningPlanet
    const banner = this.root.querySelector("#planetary-proximity-warning")
    const announcement = this.root.querySelector("#planetary-proximity-announcement")

    if (banner) {
      banner.hidden = !view
      banner.dataset.level = nextLevel
      banner.classList.toggle("border-rose-400/80", nextLevel === "critical")
      banner.classList.toggle("bg-rose-950/95", nextLevel === "critical")
      banner.classList.toggle("border-amber-400/60", nextLevel === "caution")
      banner.classList.toggle("bg-amber-950/85", nextLevel === "caution")
    }
    if (view) {
      const title = this.root.querySelector("#planetary-proximity-level")
      const detail = this.root.querySelector("#planetary-proximity-detail")
      if (title) {
        title.textContent = view.label
        title.classList.toggle("text-rose-100", view.level === "critical")
        title.classList.toggle("text-amber-100", view.level === "caution")
      }
      if (detail) detail.textContent = view.detail
    }

    if (announce && changed && announcement) {
      announcement.textContent = view?.announcement || "Planetary collision clearance restored."
    }

    this.planetaryWarningLevel = nextLevel
    this.planetaryWarningPlanet = nextPlanet
  }

  applyStationWarning(warning, {announce = true} = {}) {
    const view = stationWarningView(warning)
    const nextLevel = view?.level || "clear"
    const changed = nextLevel !== this.stationWarningLevel
    const banner = this.root.querySelector("#station-proximity-warning")
    const announcement = this.root.querySelector("#station-proximity-announcement")

    if (banner) {
      banner.hidden = !view
      banner.dataset.level = nextLevel
    }
    if (view) {
      const title = this.root.querySelector("#station-proximity-level")
      const detail = this.root.querySelector("#station-proximity-detail")
      if (title) title.textContent = view.label
      if (detail) detail.textContent = view.detail
    }
    if (announce && changed && announcement) {
      announcement.textContent = view?.announcement || "Refinery clearance restored."
    }
    this.stationWarningLevel = nextLevel
  }

  entityDestroyed(destruction) {
    const id = entityKey(destruction.entity.id)
    const isNpc = destruction.entity.kind === "npc"
    const impact = planetaryImpactMessage(destruction)
    if (isNpc) this.removeEntity(id)
    else this.upsertEntity(destruction.entity, true)
    if (this.selectedTargetId === id) this.selectedTargetId = null

    const label = impact ||
      (isNpc ? "Hostile destroyed. Respawn telemetry queued." : "Ship destroyed.")
    this.setCombatMessage(label)
    if (id === this.selfId) {
      // Server-confirmed destruction: the tactical SOL hold is canceled on
      // defeat. A fresh session recreates a ship at the departure region.
      this.exitMouseSteering({silent: true})
      this.applyPlanetaryWarning(null, {announce: false})
      this.applyStationWarning(null, {announce: false})
      this.showError(impact || (destruction.reason === "station_collision"
        ? "Ship destroyed by refinery collision. Reconnect to respawn."
        : "Ship destroyed. Reconnect to respawn at your departure region."))
    }
    this.updateCombatHud()
  }

  removeEntity(id) {
    const key = entityKey(id)
    this.entities.delete(key)
    if (this.selectedTargetId === key) this.selectedTargetId = null
    for (const entity of this.entities.values()) {
      if (entity.targetId === key) entity.targetId = null
      if (entity.engagedTargetId === key) entity.engagedTargetId = null
    }
  }

  attackError(reason) {
    const messages = {
      no_target: "Select an NPC before engaging.",
      target_not_found: "The selected target is no longer active.",
      out_of_range: "Target is outside laser range. Navigate closer.",
      weapon_cooldown: "Laser is recharging.",
      attacker_destroyed: "Destroyed ships cannot fire.",
      weapon_unarmed: "No server-authorized weapon is available.",
    }
    return messages[reason] || `Laser rejected: ${reason}`
  }

  frame(time) {
    const deltaSeconds = Math.min((time - this.lastFrame) / 1000, 0.1)
    this.lastFrame = time
    // Expire mouse commands before advancing the visible cockpit. The
    // independent idle timer can stop them between rendered frames as well.
    if (this.mouseSteeringEnabled && document.pointerLockElement === this.canvas) {
      const expired = this.mouseSteering.expire(time)
      if (expired) this.flightControls?.setMouseSteering(expired)
    }
    this.interpolate(deltaSeconds)
    this.flightControls?.heartbeat(time)
    this.spaceLaser?.update(time)
    this.draw(time)
    this.minimap?.draw(time)
    this.navComputer?.draw(time)
    this.updateCoordinates()
    this.updateCombatHud()
    requestAnimationFrame(nextTime => this.frame(nextTime))
  }

  interpolate(deltaSeconds) {
    const positionBlend = 1 - Math.exp(-deltaSeconds / 0.085)
    const pointerLocked = this.mouseSteeringEnabled &&
      document.pointerLockElement === this.canvas

    for (const entity of this.entities.values()) {
      // The local pointer-lock camera should not trail far behind the last
      // server orientation when the user releases the mouse. Remote players
      // and keyboard-only flight retain the original 85ms smoothing.
      const cameraSettle = cameraSettleSeconds({
        ownShip: entity.id === this.selfId,
        pointerLocked,
      })
      entity.render.x += (entity.target.x - entity.render.x) * positionBlend
      entity.render.y += (entity.target.y - entity.render.y) * positionBlend
      entity.render.z = (entity.render.z ?? 0) +
        ((entity.target.z ?? 0) - (entity.render.z ?? 0)) * positionBlend
      if (entity.attitude) {
        entity.renderAttitude = smoothAttitude(
          entity.renderAttitude || entity.attitude,
          entity.attitude,
          deltaSeconds,
          cameraSettle
        )
      }
      if (entity.orientation) {
        entity.renderOrientation = smoothOrientation(
          entity.renderOrientation || entity.orientation,
          entity.orientation, deltaSeconds, cameraSettle
        )
      }
    }

    const rotationBlend = 1 - Math.exp(-deltaSeconds / 0.075)
    for (const entity of this.entities.values()) {
      entity.angle = smoothAngle(
        entity.angle,
        desiredEntityAngle(entity, this.entities),
        rotationBlend
      )
    }

  }

  draw(time) {
    // A missing WebGL renderer must never silently bring back Classic 2D.
    if (!this.stereoView) return

    this.stereoView.render(this, time)
    this.beams = this.beams.filter(beam => beam.expiresAt > time)
    const feedback = this.lastLaserFeedback
    const element = this.root.querySelector("#laser-hit-confirmation")
    if (element) {
      const active = feedback && time - feedback.at < LASER_FEEDBACK_MS
      element.classList.toggle("hidden", !active)
      if (active) {
        element.textContent = feedback.label
        element.classList.toggle("text-emerald-200", feedback.hit)
        element.classList.toggle("text-rose-200", !feedback.hit)
        element.classList.toggle("border-emerald-400/50", feedback.hit)
        element.classList.toggle("border-rose-400/50", !feedback.hit)
      }
    }
  }

  // The browser page renders hotbar slots in HEEx. The installed client
  // instead receives the same authoritative action catalog on Channel join.
  populateNativeHotbar(hotbar) {
    for (const entry of hotbar) {
      const slot = this.root.querySelector('[data-hotbar-slot="' + entry.slot + '"]')
      if (!slot) continue
      const action = entry.action
      if (action) {
        slot.dataset.actionId = action.id
        slot.dataset.actionType = action.type
        slot.dataset.activationMode = action.activation_mode
      } else {
        delete slot.dataset.actionId
        delete slot.dataset.actionType
        delete slot.dataset.activationMode
      }
      const label = slot.querySelector("[data-hotbar-label]")
      if (label) label.textContent = action?.label || "Empty"
      slot.setAttribute("aria-label", action ? entry.key + " " + action.label : entry.key + " Empty")
      slot.classList.toggle("hotbar-slot-empty", !action)
    }
  }

  populateHud() {
    const {pilot, ship, stats, configuration} = this.player
    this.text("#hud-pilot", pilot.pilot_name)
    this.text("#hud-ship", `${ship.name} · Pilot #${pilot.id}`)
    this.text("#hud-config", `C-${configuration.number}`)
    this.text("#hud-hp", `${number(stats.hit_points)} / ${number(stats.hit_points)}`)
    this.text("#hud-shields", `${number(stats.shields)} / ${number(stats.shields)}`)
    this.text("#hud-compact-hp", number(stats.hit_points))
    this.text("#hud-compact-shields", number(stats.shields))
    this.text("#hud-speed", `${number(stats.speed)} u/s`)
    this.root.querySelector("#hud-hp-bar").style.width = "100%"
    this.root.querySelector("#hud-shield-bar").style.width = stats.shields > 0 ? "100%" : "0%"

    const equipment = [...configuration.lasers, ...configuration.generators, ...configuration.drones]
    this.text(
      "#hud-equipment",
      equipment.length ? equipment.map(item => item.name).join(" · ") : "Garnet laser (10) · Forward-1 shield · Standard missile tube"
    )
  }

  updateCoordinates() {
    const ownShip = this.entities.get(this.selfId)
    if (!ownShip) return
    this.text("#hud-coordinates", `${number(ownShip.render.x)} / ${number(ownShip.render.y)} / ${number(ownShip.render.z)}`)
    this.text("#hud-flight-mode", (ownShip.flightMode || "cruise").toUpperCase())
    this.text("#hud-throttle", `${Math.round((ownShip.throttle || 0) * 100)}%`)
    const v = ownShip.velocity || {x: 0, y: 0, z: 0}
    this.text("#hud-actual-speed", `${Math.round(Math.hypot(v.x, v.y, v.z))} u/s`)
    const a = orientationTelemetry(
      ownShip.orientation, ownShip.attitude || {yaw: 0, pitch: 0, roll: 0}
    )
    const deg = radians => Math.round(radians * 180 / Math.PI)
    this.text("#hud-heading", `${(deg(a.yaw) + 360) % 360}°`)
    this.text("#hud-pitch", `${deg(a.pitch)}°`)
    this.text("#hud-roll", `${deg(a.roll)}°`)
    const r = ownShip.angularVelocity || {yaw: 0, pitch: 0, roll: 0}
    this.text("#hud-turn-rates",
      `${Math.round(Math.abs(deg(r.pitch)))} / ${Math.round(Math.abs(deg(r.yaw)))} / ${Math.round(Math.abs(deg(r.roll)))} °/s`)
    const input = this.flightControls?.axes().pitch || 0
    this.text("#hud-pitch-input", input < 0 ? "DOWN" : input > 0 ? "UP" : "—")
  }

  updateNavigationStatus() {
    const ownShip = this.entities.get(this.selfId)
    let status = "Awaiting sector link"

    if (ownShip?.status === "destroyed") {
      status = "Navigation unavailable"
    } else if (this.commandDestination) {
      status = `Course locked · ${number(this.commandDestination.x)} / ${number(this.commandDestination.y)} / ${number(this.commandDestination.z)}`
    } else if (ownShip) {
      status = "Press M for atlas navigation"
    }

    this.text("#minimap-navigation-status", status)
  }

  updateCombatHud() {
    const ownShip = this.entities.get(this.selfId)
    if (ownShip) {
      this.text("#hud-hp", `${number(ownShip.hull)} / ${number(ownShip.maxHull)}`)
      this.text("#hud-shields", `${number(ownShip.shields)} / ${number(ownShip.maxShields)}`)
      this.text("#hud-compact-hp", number(ownShip.hull))
      this.text("#hud-compact-shields", number(ownShip.shields))
      this.setWidth("#hud-hp-bar", healthPercent(ownShip.hull, ownShip.maxHull))
      this.setWidth("#hud-shield-bar", healthPercent(ownShip.shields, ownShip.maxShields))
    }

    this.updateHotbar()
  }

  updateHotbar() {
    const ownShip = this.entities.get(this.selfId)
    const engaged = Boolean(ownShip?.engagedTargetId)
    const nextAttackTick = Number(ownShip?.nextAttackTick) || 0
    const cooldownTicks = Math.max(1, Number(ownShip?.attackCooldownTicks) || 1)
    const remainingTicks = Math.max(0, nextAttackTick - this.worldTick)
    const cooldownPercent = Math.min(100, remainingTicks / cooldownTicks * 100)

    for (const slot of this.root.querySelectorAll("[data-hotbar-slot]")) {
      const slotNumber = Number(slot.dataset.hotbarSlot)
      const hasAction = slot.dataset.actionId != null
      const action = {
        type: slot.dataset.actionType,
        activationMode: slot.dataset.activationMode,
      }
      const active = hasAction && hotbarActionActive(action, engaged)
      const coolingDown = hasAction && action.type === "ammunition" && remainingTicks > 0
      slot.classList.toggle("is-selected", slotNumber === this.selectedHotbarSlot)
      slot.classList.toggle("is-active", active)
      slot.classList.toggle("is-cooling-down", coolingDown)
      slot.setAttribute("aria-pressed", active ? "true" : "false")

      const cooldown = slot.querySelector("[data-hotbar-cooldown]")
      if (cooldown) cooldown.style.height = `${coolingDown ? cooldownPercent : 0}%`
    }

    this.text("#hotbar-mode", engaged ? "AUTOFIRE" : "STANDBY")
  }

  setWidth(selector, percentage) {
    const element = this.root.querySelector(selector)
    if (element) element.style.width = `${percentage}%`
  }

  setCombatMessage(message) {
    this.text("#combat-status", message)
  }

  resize() {
    const rect = this.canvas.getBoundingClientRect()
    const dpr = Math.min(window.devicePixelRatio || 1, 2)
    this.stereoView?.resize(rect.width, rect.height, dpr)
  }

  scheduleMouseStop() {
    window.clearTimeout(this.mouseIdleTimer)
    // Mouse movement cannot emit its own "stopped" event. An independent
    // timer sends neutral without waiting for the next animation frame.
    this.mouseIdleTimer = window.setTimeout(() => {
      this.mouseIdleTimer = null
      if (!this.mouseSteeringEnabled ||
          document.pointerLockElement !== this.canvas ||
          !this.flightControls?.active()) return
      const expired = this.mouseSteering.expire(performance.now())
      if (expired) this.flightControls.setMouseSteering(expired)
    }, MOUSE_STEERING_IDLE_MS)
  }

  setupMouseSteering() {
    const toggle = this.root.querySelector("#nav-mouse-steering")
    const slider = this.root.querySelector("#nav-mouse-sensitivity")
    const output = this.root.querySelector("#nav-mouse-sensitivity-value")
    if (toggle) toggle.checked = this.mouseSteeringEnabled
    if (slider) slider.value = String(Math.round(this.mouseSteeringSensitivity * 100))
    if (output) output.textContent = this.mouseSteeringSensitivity.toFixed(1) + "×"
    slider?.addEventListener("input", () => {
      const sensitivity = Number(slider.value) / 100
      if (!validMouseSensitivity(sensitivity)) return
      this.mouseSteeringSensitivity = sensitivity
      this.mouseSteering.sensitivity = sensitivity
      localStorage.setItem(this.mouseSensitivityKey, String(sensitivity))
      if (output) output.textContent = sensitivity.toFixed(1) + "×"
    })
    toggle?.addEventListener("change", () => {
      this.mouseSteeringEnabled = toggle.checked
      localStorage.setItem(this.mouseSteeringKey, toggle.checked ? "1" : "0")
      if (!toggle.checked) this.exitMouseSteering({silent: this.navComputer?.isOpen})
      this.updateMouseSteeringStatus()
    })

    this.canvas.addEventListener("pointerdown", event => {
      if (!this.mouseSteeringEnabled || event.button !== 0 ||
          document.pointerLockElement === this.canvas ||
          this.navComputer?.isOpen || this.inSystemCruise() ||
          !this.flightControls.active()) return

      // A direct cockpit click is required by the browser for pointer lock.
      // Consume this FIRST click so it never selects a target accidentally.
      event.preventDefault()
      event.stopImmediatePropagation()
      this.canvas.focus({preventScroll: true})
      if (!this.canvas.requestPointerLock) {
        this.mouseSteeringMessage("Pointer lock unavailable; keyboard steering remains active.")
        return
      }
      try {
        this.mouseCaptureLost = false
        const request = this.canvas.requestPointerLock()
        request?.catch?.(() =>
          this.mouseSteeringMessage("Mouse capture was denied. Click the cockpit to retry."))
      } catch (_error) {
        this.mouseSteeringMessage("Mouse capture unavailable; keyboard steering remains active.")
      }
    }, true)

    document.addEventListener("mousemove", event => {
      if (!this.mouseSteeringEnabled || document.pointerLockElement !== this.canvas ||
          this.navComputer?.isOpen || this.inSystemCruise() ||
          !this.flightControls.active()) return
      // Zero-delta browser events must not extend steering beyond the
      // last physical movement. In particular, do not restart the timer.
      if (!Number.isFinite(event.movementX) ||
          !Number.isFinite(event.movementY) ||
          (event.movementX === 0 && event.movementY === 0)) return
      const axes = this.mouseSteering.move(event.movementX, event.movementY)
      this.flightControls.setMouseSteering(axes)
      this.scheduleMouseStop()
    })
    document.addEventListener("pointerlockchange", () => {
      window.clearTimeout(this.mouseIdleTimer)
      this.mouseIdleTimer = null
      const captured = this.mouseSteeringEnabled &&
        document.pointerLockElement === this.canvas
      if (captured) {
        this.mouseCaptureLost = false
      } else if (this.mouseSteeringEnabled && !this.navComputer?.isOpen &&
                 !this.inSystemCruise()) {
        // A lost pointer lock is an actual input pause, not a lost setting.
        // The browser requires another physical click before recapturing.
        this.mouseCaptureLost = true
      }
      // Use the faster mouse-only angular rate profile on the server ONLY
      // during pointer capture, reverting when the cursor is released.
      if (!captured) {
        this.mouseSteering.release()
        this.flightControls.clearMouseSteering({silent: true})
      }
      this.flightControls.setMouseMode(captured, {
        silent: Boolean(this.navComputer?.isOpen || this.inSystemCruise()),
      })
      this.updateMouseSteeringStatus()
    })
    document.addEventListener("pointerlockerror", () =>
      this.mouseSteeringMessage("Mouse capture failed. Try clicking the cockpit again."))

    // Escape first releases the cursor rather than accidentally disengaging
    // combat; M still opens Atlas, which releases the mouse automatically.
    window.addEventListener("keydown", event => {
      if (event.code !== "Escape" || document.pointerLockElement !== this.canvas) return
      event.preventDefault()
      event.stopImmediatePropagation()
      this.exitMouseSteering()
    }, true)
    this.updateMouseSteeringStatus()
  }

  mouseSteeringMessage(message) {
    const node = this.root.querySelector("#cockpit-mouse-steering-status")
    if (!node || !this.mouseSteeringEnabled) return
    node.hidden = false
    node.textContent = message
  }

  updateMouseSteeringStatus() {
    const node = this.root.querySelector("#cockpit-mouse-steering-status")
    if (!node) return
    node.hidden = !this.mouseSteeringEnabled || Boolean(this.navComputer?.isOpen)
    if (node.hidden) return
    const captured = document.pointerLockElement === this.canvas
    node.textContent = captured
      ? "MOUSE STEERING ACTIVE · MOVE TO PITCH/YAW · ESC RELEASES"
      : this.mouseCaptureLost
        ? "MOUSE STEERING PAUSED · CLICK COCKPIT TO RESUME"
        : "MOUSE STEERING ENABLED · CLICK COCKPIT TO CAPTURE"
  }

  exitMouseSteering({silent = false} = {}) {
    window.clearTimeout(this.mouseIdleTimer)
    this.mouseIdleTimer = null
    this.mouseSteering.release()
    this.flightControls?.clearMouseSteering({silent: true})
    this.flightControls?.setMouseMode(false, {silent})
    if (document.pointerLockElement === this.canvas) document.exitPointerLock?.()
    this.updateMouseSteeringStatus()
  }

  handleHelmetAlignmentKey(event) {
    // Reserve calibration shortcuts in cockpit mode, whether or not the
    // headset is already rendering. Arrow keys must never scroll the DOM.
    // No change is emitted for OS key-repeat, duplicates, text fields,
    // Atlas input, or a suspended/closed cockpit.
    const action = this.helmetAlignmentKeys.keyDown(event, {
      active: !this.navComputer?.isOpen && !this.solarEncounter,
      typing: gameplayTypingTarget(event.target),
    })
    if (!action.reserved) return
    event.preventDefault()
    event.stopPropagation()

    if (action.intent && this.helmet?.canAdjustAlignment())
      this.helmet.adjustAlignment(action.intent.axis, action.intent.direction)
  }

  handleDisplayModeKey(event) {
    // When the mouse owns flight steering, ignore accidental V presses that
    // would switch the cockpit view mid-maneuver. The header view selector and
    // V shortcut still work once the mouse is released with Escape.
    if (this.mouseSteeringEnabled && document.pointerLockElement === this.canvas &&
        (event.code === "KeyV" || event.key?.toLowerCase() === "v")) {
      event.preventDefault()
      return
    }
    if (event.defaultPrevented || this.navComputer?.isOpen) return
    if (event.repeat || event.ctrlKey || event.altKey || event.metaKey || event.key.toLowerCase() !== "v") return
    const element = event.target
    if (element?.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(element?.tagName)) return
    event.preventDefault()
    this.setDisplayMode(nextFlightMode(this.displayMode))
  }

  setDisplayMode(mode) {
    if (!validFlightMode(mode)) return false
    if (!this.stereoView) {
      try {
        this.stereoView = new StereoSpaceView(this.root.querySelector("#space-viewport-3d"))
      } catch (_error) {
        this.showError("WebGL is required for the 3D cockpit. Check browser GPU support.")
        const select = this.root.querySelector("#display-mode")
        if (select) select.value = "3d"
        return false
      }
    }
    this.navigation?.cancel()
    this.displayMode = mode
    this.root.dataset.displayMode = mode
    const select = this.root.querySelector("#display-mode")
    if (select) select.value = mode
    this.stereoView.setMode(mode)
    this.resize()
    return true
  }

  setConnection(label, state) {
    this.text("#connection-status", label)
    const indicator = this.root.querySelector("#connection-indicator")
    indicator.className = state === "online"
      ? "size-1.5 rounded-full bg-emerald-300 shadow-[0_0_10px_rgba(110,231,183,0.8)]"
      : "size-1.5 rounded-full bg-rose-400 shadow-[0_0_10px_rgba(251,113,133,0.8)]"
  }

  showError(message) {
    const element = this.root.querySelector("#game-error")
    element.textContent = message
    element.classList.remove("hidden")
    window.clearTimeout(this.errorTimer)
    this.errorTimer = window.setTimeout(() => element.classList.add("hidden"), 6000)
  }

  text(selector, value) {
    const element = this.root.querySelector(selector)
    if (element) element.textContent = value
  }
}

export const startGameClient = () => {
  const root = document.querySelector("#game-client")
  if (root) new SpaceClient(root).start()
}
