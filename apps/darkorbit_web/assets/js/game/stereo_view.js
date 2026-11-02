import * as THREE from "three"
import {pointerNdc, toScene, toWorld} from "./stereo_math.mjs"
import {cockpitHudFit, HUD_GEOMETRY} from "./stereo_layout.mjs"

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

function shipModel(npc) {
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
    const grid = new THREE.GridHelper(1500, 75, 0x1a4c6b, 0x0d263c)
    grid.position.set(450, -7, 350)
    this.scene.add(grid)
    this.addStars()
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
    this.scene.add(new THREE.Points(geometry, new THREE.PointsMaterial({color: 0xc8e3ff, size: 1.3})))
  }

  addCockpit() {
    const framing = new THREE.Group()
    const steel = material(0x183d5b)
    // Keep canopy struts near the outside of each eye's view; the previous
    // inward-leaning supports cut across the center and distracted from space.
    framing.add(beam([-2.0, -0.96, -2.75], [-1.75, 1.0, -3.25], 0.023, steel))
    framing.add(beam([2.0, -0.96, -2.75], [1.75, 1.0, -3.25], 0.023, steel))
    framing.add(beam([-2.0, -0.96, -2.75], [2.0, -0.96, -2.75], 0.028, steel))
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
    this.camera.add(framing)
  }

  setMode(mode) {
    this.mode = mode === "sbs" ? "sbs" : "3d"
    this.resize(this.size.width, this.size.height, this.size.dpr)
  }

  resize(width, height, dpr) {
    this.size = {width: Math.max(1, width), height: Math.max(1, height), dpr: Math.min(1.5, dpr)}
    this.renderer.setPixelRatio(this.size.dpr)
    this.renderer.setSize(this.size.width, this.size.height, false)
    this.camera.aspect = (this.mode === "sbs" ? this.size.width / 2 : this.size.width) / this.size.height
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
    this.camera.position.set(pos.x, 2.75, pos.z)
    this.camera.lookAt(pos.x + Math.cos(angle) * 50, 0.0, pos.z + Math.sin(angle) * 50)
    this.camera.updateMatrixWorld(true)
  }

  syncShips(client) {
    const active = new Set()
    for (const entity of client.entities.values()) {
      if (entity.id === client.selfId || entity.status === "destroyed") continue
      active.add(entity.id)
      let node = this.nodes.get(entity.id)
      if (!node || node.userData.kind !== entity.kind) {
        if (node) {
          this.scene.remove(node)
          disposeMesh(node)
        }
        node = shipModel(entity.kind === "npc")
        node.userData.entityId = entity.id
        node.userData.kind = entity.kind
        this.scene.add(node)
        this.nodes.set(entity.id, node)
      }
      const pos = toScene(entity.render)
      node.position.set(pos.x, entity.kind === "npc" ? 1.8 : 1.2, pos.z)
      node.rotation.y = -entity.angle
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
      const geo = new THREE.BufferGeometry().setFromPoints([
        new THREE.Vector3(from.x, 1.5, from.z),
        new THREE.Vector3(to.x, 1.5, to.z),
      ])
      const fraction = clamp((beamData.expiresAt - time) / Math.max(1, beamData.expiresAt - beamData.startedAt), 0, 1)
      const beam = new THREE.Line(geo, new THREE.LineBasicMaterial({
        color: beamData.hostile ? 0xff9f63 : 0x56dbf8,
        opacity: fraction,
        transparent: true,
      }))
      this.beamGroup.add(beam)
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
    ctx.fillText("SECTOR 1-1 / COCKPIT", 30, 65)
    ctx.font = "30px monospace"
    const hp = own ? Math.round(100 * (own.hull || 0) / Math.max(own.maxHull || 1, 1)) : 0
    const shield = own ? Math.round(100 * (own.shields || 0) / Math.max(own.maxShields || 1, 1)) : 0
    ctx.fillText("HULL " + hp + "%   SHIELD " + shield + "%", 30, 135)
    ctx.fillStyle = selected ? "#ffbe89" : "#7aa9cb"
    ctx.fillText(selected ? "TARGET " + (selected.displayName || "HOSTILE").slice(0, 23) : "NO TARGET / V: CHANGE VIEW", 30, 199)
    this.hudTexture.needsUpdate = true
  }

  render(client, time) {
    this.setCamera(client.entities.get(client.selfId))
    this.syncShips(client)
    this.syncBeams(client, time)
    this.updateHud(client, time)
    this.stereo.update(this.camera)
    const {width, height} = this.size
    if (this.mode === "sbs") {
      const half = width / 2
      this.renderer.setScissorTest(true)
      this.renderer.setViewport(0, 0, half, height)
      this.renderer.setScissor(0, 0, half, height)
      this.renderer.render(this.scene, this.stereo.cameraL)
      this.renderer.setViewport(half, 0, width - half, height)
      this.renderer.setScissor(half, 0, width - half, height)
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
