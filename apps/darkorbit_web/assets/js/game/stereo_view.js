import * as THREE from "three"
import {pointerNdc, toScene, toWorld} from "./stereo_math.mjs"
import {stereoViewports, inwardStereoProjectionOffset} from "./stereo_viewport.mjs"
import {cockpitHudFit, HUD_GEOMETRY} from "./stereo_layout.mjs"
import {flightBasis, degrees} from "./flight_basis.mjs"
import {orientationTelemetry} from "./orientation_interpolation.mjs"
import {targetRange, LASER_FEEDBACK_MS} from "./laser_feedback.mjs"
import {createDartModel, isDartModelId, dartHeadingRotation} from "./dart_model.mjs"
import {createScowModel, isScowModelId} from "./scow_model.mjs"
import {PlanetaryBody} from "./planetary_body.js"
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

function shipModel(npc, npcTypeId = null) {
  if (npc && isDartModelId(npcTypeId)) return createDartModel(THREE)
  if (npc && isScowModelId(npcTypeId)) return createScowModel(THREE)
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
    this.encounterShip = new EncounterShipVisual(THREE, this.scene)
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

    const sight = new THREE.Mesh(
      new THREE.RingGeometry(0.025, 0.035, 40),
      new THREE.MeshBasicMaterial({color: 0x78e6fc, transparent: true, opacity: 0.8, depthTest: false}),
    )
    sight.position.z = -5
    sight.renderOrder = 50
    framing.add(sight)
    this.sight = sight
    this.camera.add(framing)
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
          node.userData.npcTypeId !== (entity.npcTypeId || null)) {
        if (node) {
          this.scene.remove(node)
          disposeMesh(node)
        }
        node = shipModel(entity.kind === "npc", entity.npcTypeId)
        node.userData.entityId = entity.id
        node.userData.kind = entity.kind
        node.userData.npcTypeId = entity.npcTypeId || null
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
        (isDartModelId(entity.npcTypeId) || isScowModelId(entity.npcTypeId))) {
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
    ctx.fillStyle = recent ? (feedback.hit ? "#81ffaf" : "#ff9a99") :
      selected ? "#ffbe89" : "#7aa9cb"
    ctx.font = recent ? "bold 36px monospace" : "30px monospace"
    ctx.fillText(recent ? feedback.label :
      selected ? "TARGET " + (selected.displayName || "HOSTILE").slice(0, 23) :
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
      : flyby ? "#7eead6"
      : range?.inRange === false ? "#ff9b96" : "#9fc7df"
    ctx.font = "bold 22px monospace"
    ctx.fillText(planetWarning
      ? planetWarning.level.toUpperCase() + " · " + planetWarning.detail
      : flyby ? "CLOSE PASS · " + String(flyby.call_sign).slice(0, 24) +
        " · HAIL VIA ATLAS"
      : range ? range.label :
        "LASER " + Math.round(own?.attackRange || 0) + "u  ·  RMB FIRE  ·  T TARGET",
      30, 234)
    this.hudTexture.needsUpdate = true
  }

  render(client, time) {
    const feedback = client.lastLaserFeedback
    const active = feedback && time - feedback.at < LASER_FEEDBACK_MS
    this.sight?.material?.color?.setHex(active ?
      feedback.hit ? 0x79ff9b : 0xff7272 : 0x78e6fc)
    const ownShip = client.entities.get(client.selfId)
    this.setCamera(ownShip)
    // Keep the distant starfield surrounding the pilot even in large
    // planet-centred maps. Stars are an infinite visual background.
    this.stars?.position.copy(this.camera.position)
    // Keep the actual local planet collision visual, but hide the distant
    // strategic traffic avatar once its tactical Dart opponent is present.
    const navigation = client.navComputer?.solarNavigation
    this.planetaryBody.update(navigation, this.camera, time, ownShip)
    this.encounterShip.update(navigation?.tactical_encounter ? null : navigation, this.camera)
    this.syncShips(client)
    this.syncBeams(client, time)
    this.updateHud(client, time)
    this.stereo.update(this.camera)
    const {width, height} = this.size
    if (this.mode === "sbs") {
      const {left, right} = stereoViewports(width, height, this.eyeGapPx)

      // When the physical center strip reaches zero, ArrowLeft still brings
      // the apparent two images together by changing their optical projection
      // centers. Scissoring keeps each eye in its own half of the display.
      const shift = inwardStereoProjectionOffset(this.eyeGapPx, left.width)
      this.stereo.cameraL.projectionMatrix.elements[8] -= shift
      this.stereo.cameraR.projectionMatrix.elements[8] += shift
      // Clear the center strip instead of leaving stale pixels from a prior frame.
      this.renderer.setScissorTest(false)
      this.renderer.clear(true, true, true)
      this.renderer.setScissorTest(true)
      this.renderer.setViewport(left.x, left.y, left.width, left.height)
      this.renderer.setScissor(left.x, left.y, left.width, left.height)
      this.renderer.render(this.scene, this.stereo.cameraL)
      this.renderer.setViewport(right.x, right.y, right.width, right.height)
      this.renderer.setScissor(right.x, right.y, right.width, right.height)
      this.renderer.render(this.scene, this.stereo.cameraR)
      this.renderer.setScissorTest(false)
    } else {
      this.renderer.setViewport(0, 0, width, height)
      this.renderer.render(this.scene, this.camera)
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
    if (!this.rayFromPointer(pointer, rect)) return null
    const intersections = this.raycaster.intersectObjects(this.pickables, true)
    for (const intersection of intersections) {
      let node = intersection.object
      while (node && !node.userData.entityId) node = node.parent
      if (node?.userData.kind === "npc") return node.userData.entityId
    }
    return null
  }

  destination(pointer, rect, bounds) {
    if (!this.rayFromPointer(pointer, rect)) return null
    const point = this.raycaster.ray.intersectPlane(this.floor, new THREE.Vector3())
    if (!point) return null
    const xy = toWorld(point)
    if (![xy.x, xy.y].every(Number.isFinite)) return null
    return {x: clamp(xy.x, 0, bounds.width), y: clamp(xy.y, 0, bounds.height)}
  }
}
