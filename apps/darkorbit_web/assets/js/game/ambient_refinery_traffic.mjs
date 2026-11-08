// Purely decorative orbital logistics. This is intentionally absent from
// Phoenix world entities, targeting, collisions, navigation, and the minimap.
// Each drone uses the *rendered* planet/station proxies so the visible lanes
// connect on screen even when their distant geometry is camera-compressed.
// Server station coordinates and the planetary collision hull are untouched.

export const AMBIENT_DRONE_COUNT = 20
const DRONES_PER_DIRECTION = AMBIENT_DRONE_COUNT / 2
const UP = {x: 0, y: 1, z: 0}
const X_AXIS = {x: 1, y: 0, z: 0}
const validPoint = p => p && [p.x, p.y, p.z].every(Number.isFinite)
const clamp = (n, low, high) => Math.min(high, Math.max(low, n))
const add = (a, b) => ({x: a.x + b.x, y: a.y + b.y, z: a.z + b.z})
const sub = (a, b) => ({x: a.x - b.x, y: a.y - b.y, z: a.z - b.z})
const mul = (p, scale) => ({x: p.x * scale, y: p.y * scale, z: p.z * scale})
const len = p => Math.hypot(p.x, p.y, p.z)
const normalized = p => mul(p, 1 / (len(p) || 1))
const cross = (a, b) => ({
  x: a.y * b.z - a.z * b.y,
  y: a.z * b.x - a.x * b.z,
  z: a.x * b.y - a.y * b.x,
})

// Four distinct curved lanes: two refinery-to-atmosphere supply lanes and
// two atmosphere-to-refinery resource lanes. Each has five looping drones.
export function refineryDroneRoutes(station, planet, radius, stationScale = 1) {
  if (!validPoint(station) || !validPoint(planet) ||
      !Number.isFinite(radius) || radius <= 0 ||
      !Number.isFinite(stationScale) || stationScale <= 0) return null

  const radial = sub(station, planet)
  const separation = len(radial)
  if (separation < 20) return null
  const outward = mul(radial, 1 / separation)
  const lateral = normalized(cross(outward, Math.abs(outward.y) < 0.94 ? UP : X_AXIS))
  const lift = normalized(cross(lateral, outward))
  // Slightly above the visible atmosphere: no low-altitude surface clipping.
  let surface = add(planet, mul(outward, radius * 1.055))
  const dock = add(station, mul(outward, -clamp(11 * stationScale, 2, 11)))
  const laneGap = clamp(separation * 0.04, 7, 25)
  // Near the visible limb, camera projection can put the refinery and
  // atmosphere endpoints almost on top of each other. Route to a nearby
  // atmospheric entry point rather than removing drone traffic entirely.
  // This changes *only* decorative geometry, never planetary or base physics.
  if (len(sub(dock, surface)) < 95) {
    const angled = normalized(add(outward, mul(lateral, 0.32)))
    surface = add(planet, mul(angled, radius * 1.055))
  }

  return [-1.5, -0.5, 0.5, 1.5].map((lane, index) => {
    const offset = mul(lateral, lane * laneGap)
    const elevation = mul(lift, (index % 2 ? -0.35 : 0.35) * laneGap)
    const p0 = add(dock, add(mul(offset, 0.50), mul(elevation, 0.35)))
    const p3 = add(surface, add(mul(offset, 0.95), mul(elevation, 0.30)))
    const traverse = sub(p3, p0)
    const bend = add(mul(offset, 0.62), mul(elevation, 0.8))
    return {
      lane: index,
      direction: index < 2 ? "outbound" : "inbound",
      p0,
      p1: add(p0, add(mul(traverse, 0.28), bend)),
      p2: add(p0, add(mul(traverse, 0.72), mul(bend, 1.2))),
      p3,
    }
  })
}

export function sampleDroneRoute(route, t) {
  if (!route || ![route.p0, route.p1, route.p2, route.p3].every(validPoint) ||
      !Number.isFinite(t)) return null
  t = clamp(t, 0, 1)
  const a = 1 - t
  const point = add(
    add(mul(route.p0, a * a * a), mul(route.p1, 3 * a * a * t)),
    add(mul(route.p2, 3 * a * t * t), mul(route.p3, t * t * t)),
  )
  const tangent = add(
    add(mul(sub(route.p1, route.p0), 3 * a * a),
      mul(sub(route.p2, route.p1), 6 * a * t)),
    mul(sub(route.p3, route.p2), 3 * t * t),
  )
  return {point, tangent: normalized(tangent)}
}

// Reproducible staggered stream; no unseeded randomness and no per-frame
// network events. Endpoints shrink to zero, avoiding popping near the planet.
export function droneFrame(timeMs, index, direction) {
  if (!Number.isFinite(timeMs) || !Number.isInteger(index) ||
      index < 0 || index >= DRONES_PER_DIRECTION ||
      !["outbound", "inbound"].includes(direction)) return null
  const slot = Math.floor(index / 2)
  const jitter = ((index * 37 + (direction === "outbound" ? 11 : 23)) % 19) / 19
  const duration = 21 + jitter * 6
  const progress = ((Math.max(0, timeMs) / 1000 / duration +
    (slot + jitter * 0.3) / (DRONES_PER_DIRECTION / 2)) % 1)
  const fade = clamp(Math.min(progress, 1 - progress) / 0.12, 0, 1)
  return {progress, fade, pathT: direction === "inbound" ? 1 - progress : progress}
}

export class AmbientRefineryTraffic {
  constructor(THREE, scene) {
    this.THREE = THREE
    this.scene = scene
    this.meshes = []
    this.geometry = null
    this.dummy = new THREE.Object3D()
    this.forward = new THREE.Vector3(0, 1, 0)
    this.tangent = new THREE.Vector3()
  }

  create() {
    if (this.meshes.length) return
    const T = this.THREE
    const geometry = new T.ConeGeometry(1.0, 3.1, 5)
    const materials = [
      new T.MeshBasicMaterial({
        color: 0xffc078, transparent: true, opacity: 0.86,
        blending: T.AdditiveBlending, depthWrite: false,
      }),
      new T.MeshBasicMaterial({
        color: 0x7deaff, transparent: true, opacity: 0.92,
        blending: T.AdditiveBlending, depthWrite: false,
      }),
    ]
    this.geometry = geometry
    this.meshes = materials.map(material => {
      const mesh = new T.InstancedMesh(geometry, material, DRONES_PER_DIRECTION)
      // Locations are updated every frame and can span a large projected lane.
      mesh.frustumCulled = false
      mesh.renderOrder = 2
      if (T.DynamicDrawUsage) mesh.instanceMatrix.setUsage(T.DynamicDrawUsage)
      this.scene.add(mesh)
      return mesh
    })
  }

  hide() {
    for (const mesh of this.meshes) mesh.visible = false
  }

  // Only the active orbital view with a *matching* server-published base
  // may display this effect. No traffic appears in cruise, combat-only
  // deep-space maps, or for a stale planet from a previous region.
  update(base, stationNode, planetBody, planetaryView, timeMs, camera) {
    if (!base || !stationNode?.visible || !planetBody?.group?.visible ||
        planetaryView?.stage !== "orbital_preview" ||
        base.body_id !== planetaryView.body_id ||
        planetBody.activeId !== base.body_id || !validPoint(camera?.position)) {
      this.hide()
      return
    }
    const routes = refineryDroneRoutes(
      stationNode.position,
      planetBody.group.position,
      planetBody.group.scale.x,
      stationNode.scale.x,
    )
    if (!routes) {
      this.hide()
      return
    }

    this.create()
    const stationDistance = len(sub(stationNode.position, camera.position))
    const size = clamp(stationDistance * 0.0045, 1.25, 3.5)
    for (let directionIndex = 0; directionIndex < 2; directionIndex++) {
      const direction = directionIndex === 0 ? "outbound" : "inbound"
      const mesh = this.meshes[directionIndex]
      mesh.visible = true
      for (let i = 0; i < DRONES_PER_DIRECTION; i++) {
        const frame = droneFrame(timeMs, i, direction)
        const route = routes[directionIndex * 2 + i % 2]
        const point = sampleDroneRoute(route, frame.pathT)
        const tangent = direction === "inbound" ? mul(point.tangent, -1) : point.tangent
        this.dummy.position.set(point.point.x, point.point.y, point.point.z)
        this.tangent.set(tangent.x, tangent.y, tangent.z)
        this.dummy.quaternion.setFromUnitVectors(this.forward, this.tangent)
        this.dummy.scale.setScalar(Math.max(0.0001, size * frame.fade))
        this.dummy.updateMatrix()
        mesh.setMatrixAt(i, this.dummy.matrix)
      }
      mesh.instanceMatrix.needsUpdate = true
    }
  }

  dispose() {
    for (const mesh of this.meshes) {
      this.scene.remove(mesh)
      mesh.material.dispose()
    }
    this.geometry?.dispose()
    this.meshes = []
    this.geometry = null
  }
}
