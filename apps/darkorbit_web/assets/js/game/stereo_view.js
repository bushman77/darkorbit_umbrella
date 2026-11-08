import * as THREE from "three"
import {pointerNdc, toScene, toWorld} from "./stereo_math.mjs"
import {stereoViewports, applyTransientStereoOffset} from "./stereo_viewport.mjs"
import {cockpitHudFit, HUD_GEOMETRY} from "./stereo_layout.mjs"
import {flightBasis, degrees} from "./flight_basis.mjs"
import {orientationTelemetry} from "./orientation_interpolation.mjs"
import {targetRange, LASER_FEEDBACK_MS} from "./laser_feedback.mjs"
import {createDartModel, dartHeadingRotation} from "./dart_model.mjs"
import {createScowModel} from "./scow_model.mjs"
import {npcVisualClass} from "./ship_model_selection.mjs"
import {surrenderedHudLabel} from "./target_hud_status.mjs"
import {PlanetaryBody} from "./planetary_body.js"
import {SpaceBaseVisual} from "./space_base_visual.js"
import {AmbientRefineryTraffic} from "./ambient_refinery_traffic.mjs"
import {GreenStarbaseVisual} from "./green_starbase_visual.js"
import {GreenStarbaseInterior, greenStarbaseInteriorVisible} from "./green_starbase_interior.js"
import {EncounterShipVisual} from "./encounter_ship.js"

// Rendering only: no Phoenix socket, no movement authority, no combat calculations.
const clamp = (value, min, max) => Math.max(min, Math.min(value, max))
const material = hex => new THREE.MeshStandardMaterial({
  color: hex, metalness: 0.45, roughness: 0.48, emissive: hex, emissiveIntensity: 0.17,
})

function beam(a, b, radius, mat) {
  const start = new THREE.Vector3(...a)
  const end = new THREE.Vector3(...b)
  const line = end.sub(start)
  const mesh = new THREE.Mesh(new THREE.CylinderGeometry(radius, radius, line.length(), 8), mat)
  mesh.position.copy(start).addScaledVector(line, 0.5)
  mesh.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), line.normalize())
  return mesh
}

function shipModel(npc, npcTypeId = null, shipClass = null) {
  const model = npc ? npcVisualClass(npcTypeId, shipClass) : "player"
  if (model === "dart") return createDartModel(THREE)
  if (model === "scow") return createScowModel(THREE)
  const root = new THREE.Group()
  const hull = new THREE.Mesh(
    npc ? new THREE.OctahedronGeometry(2, 0) : new THREE.ConeGeometry(1.65, 4.8, 4),
    material(npc ? 0xe68b44 : 0x95c8ef),
  )
  if (!npc) hull.rotation.z = -Math.PI / 2
  root.add(hull)
  if (!npc) {
    const wing = new THREE.Mesh(new THREE.BoxGeometry(1.7, 0.25, 5.5), material(0x4a718a))
    wing.position.x = -0.7
    root.add(wing)
  }
  const ring = new THREE.Mesh(new THREE.TorusGeometry(3.2, 0.08, 5, 48), new THREE.MeshBasicMaterial({color: 0xffa765}))
  ring.position.y = -1.25
  ring.rotation.x = -Math.PI / 2
  ring.visible = false
  root.add(ring)
  root.userData.ring = ring
  return root
}

// Canvas textures are painted once and reused in both SBS eyes. These are
// physical cockpit surfaces, not fixed screen overlays: head motion can
// look away from them naturally.
function cockpitLabel(lines, {width = 512, height = 256} = {}) {
  const canvas = document.createElement("canvas")
  canvas.width = width
  canvas.height = height
  const ctx = canvas.getContext("2d")
  ctx.fillStyle = "#071c22"
  ctx.fillRect(0, 0, width, height)
  ctx.strokeStyle = "#53e6ae"
  ctx.lineWidth = 10
  ctx.strokeRect(8, 8, width - 16, height - 16)
  ctx.fillStyle = "#bbffe2"
  const fontSize = Math.round(Math.min(height / (lines.length + 1.5), width / 13))
  ctx.font = "bold " + fontSize + "px monospace"
  ctx.textAlign = "center"
  lines.forEach((text, i) => ctx.fillText(text, width / 2,
    height * (i + 1) / (lines.length + 1) + fontSize / 3, width - 38))
  const texture = new THREE.CanvasTexture(canvas)
  texture.colorSpace = THREE.SRGBColorSpace
  return texture
}

function disposeMesh(root) {
  root.traverse(child => {
    child.geometry?.dispose()
    if (child.material) {
      for (const m of (Array.isArray(child.material) ? child.material : [child.material])) m.dispose()
    }
  })
}

export class StereoSpaceView {
  constructor(canvas) {
    this.canvas = canvas
    this.renderer = new THREE.WebGLRenderer({canvas, alpha: false, antialias: true, powerPreference: "high-performance"})
    this.renderer.setClearColor(0x020816)
    this.scene = new THREE.Scene()
    this.scene.background = new THREE.Color(0x020816)
    this.camera = new THREE.PerspectiveCamera(70, 1, 0.1, 3000)
    this.stereo = new THREE.StereoCamera()
    this.stereo.eyeSep = 0.064
    this.eyeGapPx = 0
    this.mode = "3d"
    this.size = {width: 1, height: 1, dpr: 1}
    this.scene.add(this.camera)
    this.nodes = new Map()
    this.pickables = []
    this.raycaster = new THREE.Raycaster()
    this.floor = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0)
    this.scene.add(new THREE.HemisphereLight(0x9cbffb, 0x0a1421, 2.3))
    const sun = new THREE.DirectionalLight(0xb6eaff, 2.1)
    sun.position.set(25, 60, 15)
    this.scene.add(sun)
    // Space has no artificial ground plane. The atlas alone owns the XY chart.
    this.addStars()
    // The spherical planet is visually scaled by its angular diameter.
    // It must not inherit the tactical map's 3,000-unit clipping limits.
    this.planetaryBody = new PlanetaryBody(THREE, this.scene)
    this.spaceBase = new SpaceBaseVisual(THREE, this.scene)
    this.refineryTraffic = new AmbientRefineryTraffic(THREE, this.scene)
    this.greenStarbase = new GreenStarbaseVisual(THREE, this.scene)
    // Keep the hangar in a separate, static scene: parked pilots are removed
    // from tactical entities and must not inherit ship camera/physics state.
    this.hangarScene = new THREE.Scene()
    this.hangarScene.background = new THREE.Color(0x03140e)
    this.hangar = new GreenStarbaseInterior(THREE, this.hangarScene)
    this.interiorActive = false
    this.encounterShip = new EncounterShipVisual(THREE, this.scene)
    // These must be initialized BEFORE addCockpit builds the VR meshes:
    // Three.js treats visible=undefined as visible, not hidden.
    this.helmetGazeEnabled = false
    this.helmetNavOpen = false
    this.helmetHeadRotation = null
    this.onHelmetGaze = null
    this.lastGazeArcProgress = -1
    this.addCockpit()
    this.beamGroup = new THREE.Group()
    this.scene.add(this.beamGroup)
    this.lastHudAt = -Infinity
  }

  addStars() {
    let seed = 0x51a7
    const rand = () => {
      seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0
      return seed / 4294967296
    }
    const positions = new Float32Array(1800 * 3)
    for (let i = 0; i < positions.length; i += 3) {
      positions[i] = (rand() - 0.5) * 2900
      positions[i + 1] = (rand() - 0.5) * 1500
      positions[i + 2] = (rand() - 0.5) * 2900
    }
    const geometry = new THREE.BufferGeometry()
    geometry.setAttribute("position", new THREE.BufferAttribute(positions, 3))
    const stars = new THREE.Points(geometry, new THREE.PointsMaterial({
      color: 0xc8e3ff, size: 1.3, depthTest: false, depthWrite: false,
    }))
    // Stars are an infinitely distant backdrop, never in front of a planet.
    stars.renderOrder = -100
    this.stars = stars
    this.scene.add(stars)
  }

  addCockpit() {
    const framing = new THREE.Group()
    const steel = material(0x183d5b)
    // Keep canopy struts near the outside of each eye's view; the previous
    // inward-leaning supports cut across the center and distracted from space.
    framing.add(beam([-2.0, -0.96, -2.75], [-1.75, 1.0, -3.25], 0.023, steel))
    framing.add(beam([2.0, -0.96, -2.75], [1.75, 1.0, -3.25], 0.023, steel))
    framing.add(beam([-2.0, -0.96, -2.75], [2.0, -0.96, -2.75], 0.028, steel))
    // Two visible wing-mounted emitters. Their tips correspond exactly to
    // Core.Combat.LineOfFire's server-owned muzzle positions: ship-local
    // (+/-1.75, +1.3, -3.2), relative to the cockpit eye at Y=+2.75.
    const emitterMetal = material(0x42576b)
    for (const side of [-1, 1]) {
      const x = side * 1.75
      framing.add(beam([x, -1.45, -2.60], [x, -1.45, -3.20],
        0.095, emitterMetal))
      const tip = new THREE.Mesh(
        new THREE.SphereGeometry(0.095, 10, 8),
        new THREE.MeshBasicMaterial({color: 0xff424a}),
      )
      tip.position.set(x, -1.45, -3.20)
      framing.add(tip)
    }
    const dash = new THREE.Mesh(new THREE.BoxGeometry(2.38, 0.72, 0.25), material(0x0d2238))
    dash.position.set(0, -0.72, -2.65)
    framing.add(dash)
    this.dash = dash

    // Draw cockpit telemetry once and present it as a stereo-correct 3D surface.
    this.hudCanvas = document.createElement("canvas")
    this.hudCanvas.width = 1024
    this.hudCanvas.height = 256
    this.hudTexture = new THREE.CanvasTexture(this.hudCanvas)
    this.hudTexture.colorSpace = THREE.SRGBColorSpace
    const panel = new THREE.Mesh(
      new THREE.PlaneGeometry(HUD_GEOMETRY.width, HUD_GEOMETRY.height),
      new THREE.MeshBasicMaterial({map: this.hudTexture}),
    )
    panel.position.set(0, HUD_GEOMETRY.centerY, -HUD_GEOMETRY.depth)
    framing.add(panel)
    this.hudPanel = panel

    // Server-owned five-second docking progress: paint locally in both eyes.
    // No per-second Phoenix events, timers with flight authority, or 2D overlays.
    this.dockingCountdownCanvas = document.createElement("canvas")
    this.dockingCountdownCanvas.width = 640
    this.dockingCountdownCanvas.height = 320
    this.dockingCountdownTexture = new THREE.CanvasTexture(this.dockingCountdownCanvas)
    this.dockingCountdownTexture.colorSpace = THREE.SRGBColorSpace
    this.dockingCountdownMesh = new THREE.Mesh(
      new THREE.PlaneGeometry(1.95, 0.98),
      new THREE.MeshBasicMaterial({
        map: this.dockingCountdownTexture, transparent: true,
        depthTest: false, depthWrite: false,
      }),
    )
    this.dockingCountdownMesh.position.set(0, 0.28, -2.27)
    this.dockingCountdownMesh.renderOrder = 82
    this.dockingCountdownMesh.visible = false
    framing.add(this.dockingCountdownMesh)
    this.lastCountdownNumber = null

    const sight = new THREE.Mesh(
      new THREE.RingGeometry(0.025, 0.035, 40),
      new THREE.MeshBasicMaterial({color: 0x78e6fc, transparent: true, opacity: 0.8, depthTest: false}),
    )
    sight.position.z = -5
    sight.renderOrder = 50
    // A center-screen sight belongs to the headset camera. The cockpit
    // itself must NOT follow head rotation; it remains ship-fixed below.
    this.camera.add(sight)
    this.sight = sight

    this.cockpitFraming = framing
    this.scene.add(framing)

    // A NAV switch mounted right of the main telemetry instrument.
    this.navSwitch = new THREE.Mesh(
      new THREE.PlaneGeometry(0.76, 0.38),
      new THREE.MeshBasicMaterial({
        map: cockpitLabel(["NAV"], {width: 512, height: 256}),
        transparent: true, depthTest: false,
      }),
    )
    // Within the narrower per-eye SBS field of view; turn right/down slightly.
    this.navSwitch.position.set(0.95, -0.64, -2.46)
    this.navSwitch.renderOrder = 68
    framing.add(this.navSwitch)

    // A simple read-only navigation display inside the same ship-fixed
    // cockpit space. Mission planning and flight remain laptop-authorized.
    this.helmetNavPanel = new THREE.Mesh(
      new THREE.PlaneGeometry(2.00, 1.08),
      new THREE.MeshBasicMaterial({
        map: cockpitLabel([
          "SOL / NAV",
          "HMD GAZE PROTOTYPE",
          "FLIGHT: LAPTOP",
          "LOOK AT CLOSE",
        ], {width: 1024, height: 600}),
        transparent: true, depthTest: false,
      }),
    )
    // Comfortable phone SBS panel, not a giant full-screen desktop billboard.
    this.helmetNavPanel.position.set(0, 0.07, -2.46)
    this.helmetNavPanel.renderOrder = 70
    framing.add(this.helmetNavPanel)
    this.helmetNavClose = new THREE.Mesh(
      new THREE.PlaneGeometry(0.70, 0.36),
      new THREE.MeshBasicMaterial({
        map: cockpitLabel(["CLOSE"], {width: 512, height: 256}),
        transparent: true, depthTest: false,
      }),
    )
    this.helmetNavClose.position.set(0.70, 0.49, -2.40)
    this.helmetNavClose.renderOrder = 71
    framing.add(this.helmetNavClose)
    this.helmetNavRecenter = new THREE.Mesh(
      new THREE.PlaneGeometry(0.96, 0.36),
      new THREE.MeshBasicMaterial({
        map: cockpitLabel(["RECENTER"], {width: 512, height: 256}),
        transparent: true, depthTest: false,
      }),
    )
    this.helmetNavRecenter.position.set(-0.60, -0.36, -2.40)
    this.helmetNavRecenter.renderOrder = 71
    framing.add(this.helmetNavRecenter)

    // Both eyes inherit the same reticle via the central camera. The
    // arc stays hidden until dwell has armed a genuine interactive target.
    this.gazeReticle = new THREE.Mesh(
      new THREE.RingGeometry(0.019, 0.026, 48),
      new THREE.MeshBasicMaterial({
        color: 0x81fbc7, transparent: true, opacity: 0.92,
        depthTest: false, depthWrite: false,
      }),
    )
    this.gazeReticle.position.set(0, 0, -1.65)
    this.gazeReticle.renderOrder = 90
    this.camera.add(this.gazeReticle)
    this.gazeArc = new THREE.Mesh(
      new THREE.RingGeometry(0.032, 0.041, 48, 1, -Math.PI / 2, 0.0001),
      new THREE.MeshBasicMaterial({
        color: 0xffdc82, depthTest: false, depthWrite: false,
      }),
    )
    this.gazeArc.position.set(0, 0, -1.65)
    this.gazeArc.renderOrder = 91
    this.camera.add(this.gazeArc)
    // Display an actionable reason in SBS when orientation sensors are not
    // usable. No such warning or gaze mesh appears in the Tauri cockpit.
    this.helmetTrackingHint = new THREE.Mesh(
      new THREE.PlaneGeometry(1.70, 0.29),
      new THREE.MeshBasicMaterial({
        map: cockpitLabel(["ENABLE HEAD TRACKING"], {width: 800, height: 138}),
        transparent: true, depthTest: false, depthWrite: false,
      }),
    )
    this.helmetTrackingHint.position.set(0, 0.88, -2.5)
    this.helmetTrackingHint.renderOrder = 72
    framing.add(this.helmetTrackingHint)
    this.setHelmetNavOpen(false)
    this.setHelmetHeadRotation(null)
  }

  setHelmetGazeEnabled(enabled) {
    this.helmetGazeEnabled = enabled === true
    // Reapply visibility even when enabling: initial construction hides
    // these physical meshes until the HMD explicitly opts into gaze mode.
    this.setHelmetNavOpen(this.helmetGazeEnabled && this.helmetNavOpen)
    this.setHelmetHeadRotation(this.helmetHeadRotation)
    this.updateGazeFeedback({target: null, armed: false, progress: 0})
  }

  setHelmetHeadRotation(quaternion) {
    this.helmetHeadRotation = quaternion &&
      [quaternion.x, quaternion.y, quaternion.z, quaternion.w].every(Number.isFinite)
      ? new THREE.Quaternion(quaternion.x, quaternion.y, quaternion.z,
        quaternion.w).normalize() : null
    if (this.gazeReticle) this.gazeReticle.visible =
      Boolean(this.helmetGazeEnabled && this.helmetHeadRotation !== null)
    if (this.helmetTrackingHint) this.helmetTrackingHint.visible =
      Boolean(this.helmetGazeEnabled && this.helmetHeadRotation === null)
    if (!this.helmetHeadRotation && this.gazeArc) this.gazeArc.visible = false
  }

  setHelmetNavOpen(open) {
    this.helmetNavOpen = open === true
    if (this.navSwitch) this.navSwitch.visible =
      Boolean(this.helmetGazeEnabled && !this.helmetNavOpen)
    if (this.helmetNavPanel) this.helmetNavPanel.visible =
      Boolean(this.helmetGazeEnabled && this.helmetNavOpen)
    if (this.helmetNavClose) this.helmetNavClose.visible =
      Boolean(this.helmetGazeEnabled && this.helmetNavOpen)
    if (this.helmetNavRecenter) this.helmetNavRecenter.visible =
      Boolean(this.helmetGazeEnabled && this.helmetNavOpen)
  }

  gazeTarget() {
    if (!this.helmetGazeEnabled || !this.helmetHeadRotation) return null
    const candidates = this.helmetNavOpen ?
      [this.helmetNavClose, this.helmetNavRecenter] : [this.navSwitch]
    this.camera.updateMatrixWorld(true)
    this.cockpitFraming.updateMatrixWorld(true)
    this.raycaster.set(this.camera.position,
      new THREE.Vector3(0, 0, -1).applyQuaternion(this.camera.quaternion))
    const hits = this.raycaster.intersectObjects(
      candidates.filter(candidate => candidate?.visible), false)
    if (!hits.length || hits[0].distance >= 6) return null
    return hits[0].object === this.helmetNavClose ? "nav_close" :
      hits[0].object === this.helmetNavRecenter ? "recenter" : "nav_open"
  }

  updateGazeFeedback({target = null, armed = false, progress = 0} = {}) {
    if (!this.gazeReticle || !this.gazeArc) return
    this.gazeReticle.material.color.setHex(target ? 0xffdb8a : 0x81fbc7)
    this.gazeArc.visible = Boolean(target && armed && progress > 0)
    if (!this.gazeArc.visible) return
    const clamped = clamp(progress, 0, 1)
    if (Math.abs(clamped - this.lastGazeArcProgress) < 0.03 && clamped < 1) return
    this.lastGazeArcProgress = clamped
    this.gazeArc.geometry.dispose()
    this.gazeArc.geometry = new THREE.RingGeometry(0.032, 0.041, 48, 1,
      -Math.PI / 2, Math.max(0.0001, clamped * Math.PI * 2))
  }

  setHelmetAlignment({eyeGapPx = this.eyeGapPx, eyeSep = this.stereo.eyeSep} = {}) {
    this.eyeGapPx = Math.min(80, Math.max(-160, Math.round(Number(eyeGapPx) || 0)))
    this.stereo.eyeSep = Math.min(0.09, Math.max(0.035, Number(eyeSep) || 0.064))
    this.resize(this.size.width, this.size.height, this.size.dpr)
  }

  setMode(mode) {
    this.mode = mode === "sbs" ? "sbs" : "3d"
    this.resize(this.size.width, this.size.height, this.size.dpr)
  }

  resize(width, height, dpr) {
    this.size = {width: Math.max(1, width), height: Math.max(1, height), dpr: Math.min(1.5, dpr)}
    this.renderer.setPixelRatio(this.size.dpr)
    this.renderer.setSize(this.size.width, this.size.height, false)
    // StereoCamera.aspect is 1 by default; it takes this camera\'s per-eye
    // aspect directly. Use the actual scissored viewport, including optical gap.
    const layout = stereoViewports(this.size.width, this.size.height, this.eyeGapPx)
    this.camera.aspect = this.mode === "sbs" ? layout.eyeAspect : this.size.width / this.size.height
    this.camera.updateProjectionMatrix()
    const fit = cockpitHudFit(this.camera.aspect, this.camera.fov)
    if (fit && this.hudPanel && this.dash) {
      this.hudPanel.scale.setScalar(fit.scale)
      this.dash.scale.setScalar(fit.scale)
    }
  }

  setCamera(ownShip) {
    if (!ownShip) return
    const pos = toScene(ownShip.render)
    const angle = Number.isFinite(ownShip.angle) ? ownShip.angle : -Math.PI / 2
    // The pilot eye is ship-local too. Rotating this offset with the ship
    // keeps the wing emitters physically anchored after rolls and loops.
    const pose = !ownShip.destination &&
      (ownShip.renderOrientation || ownShip.orientation)
    if (pose) {
      const localEye = new THREE.Vector3(0, 2.75, 0).applyQuaternion(
        new THREE.Quaternion(pose.x, pose.y, pose.z, pose.w).normalize()
      )
      this.camera.position.set(pos.x + localEye.x, pos.y + localEye.y,
        pos.z + localEye.z)
    } else {
      this.camera.position.set(pos.x, pos.y + 2.75, pos.z)
    }
    // Ship attitude is authoritative. The atlas autopilot retains its
    // independent destination-heading view.
    const attitude = ownShip.renderAttitude || ownShip.attitude ||
      {yaw: 0, pitch: 0, roll: 0}
    if (!ownShip.destination) {
      if (ownShip.renderOrientation || ownShip.orientation) {
        const q = ownShip.renderOrientation || ownShip.orientation
        this.camera.up.set(0, 1, 0)
        this.camera.quaternion.set(q.x, q.y, q.z, q.w).normalize()
        this.camera.updateMatrixWorld(true)
        return
      }
      const {forward, up} = flightBasis(attitude)
      this.camera.up.set(up.x, up.y, up.z)
      this.camera.lookAt(
        pos.x + forward.x * 100,
        pos.y + 2.75 + forward.y * 100,
        pos.z + forward.z * 100,
      )
      this.camera.updateMatrixWorld(true)
      return
    }
    // Atlas autopilot should not inherit the pilot's previous roll.
    this.camera.up.set(0, 1, 0)
    const destination = ownShip.destination ? toScene(ownShip.destination) : null
    const dx = destination ? destination.x - pos.x : 0
    const dy = destination ? destination.y - pos.y : 0
    const dz = destination ? destination.z - pos.z : 0
    if (destination && dx * dx + dy * dy + dz * dz > 0.01) {
      this.camera.lookAt(pos.x + dx, pos.y + 2.75 + dy, pos.z + dz)
    } else {
      this.camera.lookAt(pos.x + Math.cos(angle) * 50, pos.y + 2.0,
        pos.z + Math.sin(angle) * 50)
    }
    this.camera.updateMatrixWorld(true)
  }

  syncShips(client) {
    const active = new Set()
    for (const entity of client.entities.values()) {
      if (entity.id === client.selfId || entity.status === "destroyed") continue
      active.add(entity.id)
      let node = this.nodes.get(entity.id)
      if (!node || node.userData.kind !== entity.kind ||
          node.userData.npcTypeId !== (entity.npcTypeId || null) ||
          node.userData.shipClass !== (entity.shipClass || null)) {
        if (node) {
          this.scene.remove(node)
          disposeMesh(node)
        }
        node = shipModel(entity.kind === "npc", entity.npcTypeId, entity.shipClass)
        node.userData.entityId = entity.id
        node.userData.kind = entity.kind
        node.userData.npcTypeId = entity.npcTypeId || null
        node.userData.shipClass = entity.shipClass || null
        this.scene.add(node)
        this.nodes.set(entity.id, node)
      }
      const pos = toScene(entity.render)
      // Match rendered NPC centre to the server's XYZ collision sphere.
      // Decorative Y offsets previously made the reticle miss real targets.
      node.position.set(pos.x, pos.y, pos.z)
      if (entity.kind === "player" && !entity.destination && entity.orientation) {
        const q = entity.renderOrientation || entity.orientation
        node.quaternion.set(q.x, q.y, q.z, q.w).normalize()
      } else if (entity.kind === "player" && !entity.destination && entity.attitude) {
        const a = entity.renderAttitude || entity.attitude
        node.rotation.set(a.pitch, -a.yaw, a.roll, "YXZ")
      } else if (entity.kind === "npc" &&
        npcVisualClass(entity.npcTypeId, entity.shipClass) !== "generic") {
        node.rotation.y = dartHeadingRotation(entity.angle)
      } else {
        node.rotation.y = -entity.angle
      }
      node.userData.ring.visible = entity.id === client.selectedTargetId
    }
    for (const [id, node] of this.nodes) {
      if (active.has(id)) continue
      this.scene.remove(node)
      disposeMesh(node)
      this.nodes.delete(id)
    }
    this.pickables = [...this.nodes.values()].filter(node => node.userData.kind === "npc")
  }

  syncBeams(client, time) {
    for (const child of [...this.beamGroup.children]) {
      this.beamGroup.remove(child)
      disposeMesh(child)
    }
    for (const beamData of client.beams) {
      if (beamData.expiresAt <= time) continue
      const from = toScene(beamData.from)
      const to = toScene(beamData.to)
      const fraction = clamp((beamData.expiresAt - time) /
        Math.max(1, beamData.expiresAt - beamData.startedAt), 0, 1)
      const laserColor = beamData.hostile ? 0xffa35c : 0xff243d

      // Never invent local muzzle offsets here. These endpoints come from
      // the authoritative world event, including real hit/miss geometry.
      const start = [from.x, from.y, from.z]
      const finish = [to.x, to.y, to.z]
      const core = beam(start, finish, 0.13, new THREE.MeshBasicMaterial({
        color: laserColor, transparent: true, opacity: fraction,
        blending: THREE.AdditiveBlending, depthWrite: false,
      }))
      const glow = beam(start, finish, 0.32, new THREE.MeshBasicMaterial({
        color: laserColor, transparent: true, opacity: fraction * 0.32,
        blending: THREE.AdditiveBlending, depthWrite: false,
      }))
      this.beamGroup.add(core, glow)

      if (beamData.hit) {
        const flash = new THREE.Mesh(
          new THREE.SphereGeometry(1.1, 12, 8),
          new THREE.MeshBasicMaterial({
            color: beamData.hostile ? 0xffd08d : 0xffe2d8,
            transparent: true, opacity: fraction * 0.92,
            blending: THREE.AdditiveBlending, depthWrite: false,
          }),
        )
        flash.position.set(to.x, to.y, to.z)
        flash.scale.setScalar(0.9 + (1 - fraction) * 1.7)
        this.beamGroup.add(flash)
      }
    }
  }

  updateHud(client, time) {
    if (time - this.lastHudAt < 100) return
    this.lastHudAt = time
    const own = client.entities.get(client.selfId)
    const selected = client.entities.get(client.selectedTargetId)
    const surrenderLabel = surrenderedHudLabel(client)
    const ctx = this.hudCanvas.getContext("2d")
    ctx.fillStyle = "#071b2c"
    ctx.fillRect(0, 0, 1024, 256)
    ctx.strokeStyle = "#36c4de"
    ctx.lineWidth = 5
    ctx.strokeRect(8, 8, 1008, 240)
    ctx.fillStyle = "#aaf6ff"
    ctx.font = "bold 36px monospace"
    const altitude = Math.round(own?.render?.z || 0)
    const speed = own?.velocity ? Math.round(Math.hypot(own.velocity.x, own.velocity.y,
      own.velocity.z)) : 0
    const throttle = Math.round((own?.throttle || 0) * 100)
    const mode = own?.flightMode === "newtonian" ? "NF" : "CF"
    ctx.fillText("ALT " + (altitude >= 0 ? "+" : "") + altitude + "   " +
      mode + "   THR " + throttle + "%", 30, 65)
    ctx.font = "30px monospace"
    const hp = own ? Math.round(100 * (own.hull || 0) / Math.max(own.maxHull || 1, 1)) : 0
    const shield = own ? Math.round(100 * (own.shields || 0) / Math.max(own.maxShields || 1, 1)) : 0
    const attitude = orientationTelemetry(
      own?.orientation, own?.attitude || {yaw:0, pitch:0, roll:0}
    )
    const rates = own?.angularVelocity || {yaw:0, pitch:0, roll:0}
    const hdg = ((degrees(attitude.yaw) % 360) + 360) % 360
    ctx.fillText("HDG " + hdg + "  PITCH " + degrees(attitude.pitch) +
      "  ROLL " + degrees(attitude.roll) + "  V " + speed, 30, 135)
    const feedback = client.lastLaserFeedback
    const recent = feedback && time - feedback.at < LASER_FEEDBACK_MS
    ctx.fillStyle = surrenderLabel ? "#81ffaf" : recent ? (feedback.hit ? "#81ffaf" : "#ff9a99") :
      selected ? "#ffbe89" : "#7aa9cb"
    ctx.font = (surrenderLabel || recent) ? "bold 36px monospace" : "30px monospace"
    ctx.fillText(surrenderLabel ? surrenderLabel : recent ? feedback.label :
      selected ? "TARGET " +
        (npcVisualClass(selected.npcTypeId, selected.shipClass) === "generic"
          ? "" : npcVisualClass(selected.npcTypeId, selected.shipClass).toUpperCase() + " ") +
        (selected.displayName || "CONTACT").slice(0, 19) :
      "P/Y/R  " + Math.abs(degrees(rates.pitch)) + " / " +
      Math.abs(degrees(rates.yaw)) + " / " + Math.abs(degrees(rates.roll)) +
      " deg/s", 30, 194)
    const range = targetRange(own, selected)
    const nav = client.navComputer?.solarNavigation
    const flyby = nav?.tactical_encounter ? null : nav?.encounter
    const planetWarning = client.planetaryWarningDisplay
    // This canvas is a stereo-correct 3D HUD surface shared by both SBS
    // eyes. Render the hazard inside the instrument rather than a flat
    // non-stereoscopic banner that would be uncomfortable in a headset.
    ctx.fillStyle = planetWarning
      ? planetWarning.level === "critical" ? "#ff8f90" : "#ffcf7a"
      : surrenderLabel ? "#81ffaf"
      : flyby ? "#7eead6"
      : range?.inRange === false ? "#ff9b96" : "#9fc7df"
    ctx.font = "bold 22px monospace"
    ctx.fillText(planetWarning
      ? planetWarning.level.toUpperCase() + " · " + planetWarning.detail
      : surrenderLabel ? "SURRENDER OFFER · ACCEPT OR RETREAT ON LAPTOP"
      : flyby ? "CLOSE PASS · " + String(flyby.call_sign).slice(0, 24) +
        " · HAIL VIA ATLAS"
      : range ? range.label :
        "LASER " + Math.round(own?.attackRange || 0) + "u  ·  RMB FIRE  ·  T TARGET",
      30, 234)
    this.hudTexture.needsUpdate = true
  }

  updateDockingCountdown(seconds) {
    const visible = Number.isInteger(seconds) && seconds >= 0
    this.dockingCountdownMesh.visible = visible
    if (!visible || this.lastCountdownNumber === seconds) return
    this.lastCountdownNumber = seconds
    const ctx = this.dockingCountdownCanvas.getContext("2d")
    ctx.clearRect(0, 0, 640, 320)
    ctx.fillStyle = "rgba(2, 25, 19, 0.94)"
    ctx.fillRect(0, 0, 640, 320)
    ctx.strokeStyle = "#75ffb0"
    ctx.lineWidth = 12
    ctx.strokeRect(8, 8, 624, 304)
    ctx.textAlign = "center"
    ctx.fillStyle = "#8cffe0"
    ctx.font = "bold 44px monospace"
    ctx.fillText("GREEN STARBASE", 320, 78)
    ctx.fillStyle = "#f7fff5"
    ctx.font = seconds === 0 ? "bold 66px monospace" : "bold 124px monospace"
    ctx.fillText(seconds === 0 ? "DOCKING…" : String(seconds), 320, 217)
    ctx.fillStyle = "#c5dfce"
    ctx.font = "bold 30px monospace"
    ctx.fillText("HOLD STILL · AUTO DOCK", 320, 287)
    this.dockingCountdownTexture.needsUpdate = true
  }

  render(client, time) {
    const feedback = client.lastLaserFeedback
    const active = feedback && time - feedback.at < LASER_FEEDBACK_MS
    this.sight?.material?.color?.setHex(active ?
      feedback.hit ? 0x79ff9b : 0xff7272 : 0x78e6fc)
    const ownShip = client.entities.get(client.selfId)
    const docked = greenStarbaseInteriorVisible(client)
    this.updateDockingCountdown(docked ? null : client.stationDockingSeconds)
    this.interiorActive = docked
    if (docked) {
      // Station camera is an anchored viewpoint inside the actual hangar.
      // The headset still adds its own local, recentered head quaternion.
      if (this.camera.parent !== this.hangarScene) this.hangarScene.add(this.camera)
      const position = client.stationPosition
      const x = Number.isFinite(position?.x) ? position.x : 0
      const z = Number.isFinite(position?.z) ? position.z : 43
      const yaw = Number.isFinite(position?.yaw) ? position.yaw : 0
      this.camera.position.set(x, 2.6, z)
      this.camera.up.set(0, 1, 0)
      // The person's viewpoint moves, while the real ship stays parked.
      // Head tracking then adds a local quaternion for the SBS phone only.
      this.camera.rotation.set(0, -yaw, 0, "YXZ")
      this.camera.updateMatrixWorld(true)
    } else {
      if (this.camera.parent !== this.scene) this.scene.add(this.camera)
      this.setCamera(ownShip)
      // Ship-fixed cockpit surfaces stay separate from headset head motion.
      this.cockpitFraming.position.copy(this.camera.position)
      this.cockpitFraming.quaternion.copy(this.camera.quaternion)
    }
    if (this.helmetGazeEnabled && this.helmetHeadRotation) {
      this.camera.quaternion.multiply(this.helmetHeadRotation)
      this.camera.updateMatrixWorld(true)
    }
    if (this.helmetGazeEnabled && this.onHelmetGaze) {
      // In the station the laptop retains service control. Do not allow
      // invisible cockpit NAV meshes to trigger head-gaze actions.
      this.onHelmetGaze(docked ? null : this.gazeTarget(), time)
    }
    if (!docked) {
      // Real outer-space rendering is retained unchanged after launch.
      this.stars?.position.copy(this.camera.position)
      const navigation = client.navComputer?.solarNavigation
      this.planetaryBody.update(navigation, this.camera, time, ownShip)
      this.spaceBase.update(client.orbitalBase, this.camera)
      this.greenStarbase.update(navigation, client.mapId)
      this.refineryTraffic.update(client.orbitalBase, this.spaceBase.node,
        this.planetaryBody, navigation?.planetary_view, time, this.camera)
      this.encounterShip.update(navigation?.tactical_encounter ? null : navigation, this.camera)
      this.syncShips(client)
      this.syncBeams(client, time)
      this.updateHud(client, time)
    }
    this.stereo.update(this.camera)
    const activeScene = docked ? this.hangarScene : this.scene
    const {width, height} = this.size
    if (this.mode === "sbs") {
      const {left, right} = stereoViewports(width, height, this.eyeGapPx)

      // StereoCamera.update() caches its eye projections. Never permanently
      // modify elements[8] or each frame compounds the previous shift and
      // the headset image scrolls continuously without any input.
      const restore = applyTransientStereoOffset(
        this.stereo.cameraL.projectionMatrix,
        this.stereo.cameraR.projectionMatrix,
        this.eyeGapPx, left.width,
      )
      try {
        // Clear the center strip instead of leaving stale pixels from a prior frame.
        this.renderer.setScissorTest(false)
        this.renderer.clear(true, true, true)
        this.renderer.setScissorTest(true)
        this.renderer.setViewport(left.x, left.y, left.width, left.height)
        this.renderer.setScissor(left.x, left.y, left.width, left.height)
        this.renderer.render(activeScene, this.stereo.cameraL)
        this.renderer.setViewport(right.x, right.y, right.width, right.height)
        this.renderer.setScissor(right.x, right.y, right.width, right.height)
        this.renderer.render(activeScene, this.stereo.cameraR)
      } finally {
        restore()
        this.renderer.setScissorTest(false)
      }
    } else {
      this.renderer.setViewport(0, 0, width, height)
      this.renderer.render(activeScene, this.camera)
    }
  }

  rayFromPointer(pointer, rect) {
    const pos = pointerNdc(pointer, rect, this.mode)
    if (!pos) return false
    this.camera.updateMatrixWorld(true)
    this.stereo.update(this.camera)
    const camera = pos.eye === "left" ? this.stereo.cameraL : pos.eye === "right" ? this.stereo.cameraR : this.camera
    this.raycaster.setFromCamera(new THREE.Vector2(pos.x, pos.y), camera)
    return true
  }

  selectNpc(pointer, rect) {
    if (this.interiorActive || !this.rayFromPointer(pointer, rect)) return null
    const intersections = this.raycaster.intersectObjects(this.pickables, true)
    for (const intersection of intersections) {
      let node = intersection.object
      while (node && !node.userData.entityId) node = node.parent
      if (node?.userData.kind === "npc") return node.userData.entityId
    }
    return null
  }

  destination(pointer, rect, bounds) {
    if (this.interiorActive || !this.rayFromPointer(pointer, rect)) return null
    const point = this.raycaster.ray.intersectPlane(this.floor, new THREE.Vector3())
    if (!point) return null
    const xy = toWorld(point)
    if (![xy.x, xy.y].every(Number.isFinite)) return null
    return {x: clamp(xy.x, 0, bounds.width), y: clamp(xy.y, 0, bounds.height)}
  }
}
