import test from "node:test"
import assert from "node:assert/strict"
import {
  AMBIENT_DRONE_COUNT, refineryDroneRoutes,
  sampleDroneRoute, droneFrame, AmbientRefineryTraffic,
} from "./ambient_refinery_traffic.mjs"

const station = {x: 0, y: 0, z: 180}
const planet = {x: 0, y: 0, z: -800}

test("four curved lanes have two directions and visibly distinct offsets", () => {
  const lanes = refineryDroneRoutes(station, planet, 400, 1)
  assert.equal(lanes.length, 4)
  assert.deepEqual(lanes.map(l => l.direction),
    ["outbound", "outbound", "inbound", "inbound"])
  const starts = lanes.map(l => sampleDroneRoute(l, 0).point)
  const ends = lanes.map(l => sampleDroneRoute(l, 1).point)
  assert.equal(new Set(starts.map(p => p.x.toFixed(2))).size, 4)
  assert.equal(new Set(ends.map(p => p.x.toFixed(2))).size, 4)
  for (const lane of lanes) {
    assert.deepEqual(sampleDroneRoute(lane, 0).point, lane.p0)
    const last = sampleDroneRoute(lane, 1).point
    assert.ok(Math.hypot(last.x - lane.p3.x, last.y - lane.p3.y, last.z - lane.p3.z) < 1e-8)
    const mid = sampleDroneRoute(lane, 0.5)
    assert.ok([mid.point.x, mid.point.y, mid.point.z].every(Number.isFinite))
    assert.ok(Math.abs(Math.hypot(...Object.values(mid.tangent)) - 1) < 1e-8)
  }
})

test("reject invalid geometry and avoid creating lanes without spatial separation", () => {
  assert.equal(refineryDroneRoutes(station, planet, -1), null)
  assert.equal(refineryDroneRoutes({x: NaN, y: 2, z: 0}, planet, 400), null)
  assert.equal(refineryDroneRoutes(station, planet, 400, Infinity), null)
  assert.equal(refineryDroneRoutes(station, station, 400), null)
  assert.equal(sampleDroneRoute(null, 0), null)
})

test("twenty drones animate with stable phase, two lanes per direction, faded endpoints", () => {
  assert.equal(AMBIENT_DRONE_COUNT, 20)
  assert.deepEqual(droneFrame(0, 0, "outbound"), droneFrame(0, 0, "outbound"))
  const first = droneFrame(0, 0, "outbound")
  assert.equal(first.pathT, first.progress)
  const incoming = droneFrame(0, 0, "inbound")
  assert.equal(incoming.pathT, 1 - incoming.progress)
  const frames = Array.from({length: 10}, (_, i) => droneFrame(2000, i, "outbound"))
  assert.ok(new Set(frames.map(f => f.progress.toFixed(4))).size >= 5)
  assert.ok(frames.every(f => f.fade >= 0 && f.fade <= 1))
  assert.equal(droneFrame(-20, 0, "outbound").progress, first.progress)
  assert.equal(droneFrame(Infinity, 0, "inbound"), null)
  assert.equal(droneFrame(0, 10, "outbound"), null)
})

class FakeObject3D {
  constructor() {
    this.position = {set: (x, y, z) => {this.pos = {x, y, z}}}
    this.quaternion = {setFromUnitVectors: () => {}}
    this.scale = {setScalar: size => {this.size = size}}
    this.matrix = {}
  }
  updateMatrix() {this.matrix = {...this.pos, size: this.size}}
}
class FakeVector3 {
  constructor(x = 0, y = 0, z = 0) { this.x = x; this.y = y; this.z = z }
  set(x, y, z) { this.x = x; this.y = y; this.z = z; return this }
}
class FakeInstancedMesh {
  constructor(geometry, material, count) {
    this.geometry = geometry
    this.material = material
    this.count = count
    this.visible = true
    this.instanceMatrix = {needsUpdate: false, setUsage: () => {}}
    this.instances = []
  }
  setMatrixAt(index, matrix) { this.instances[index] = {...matrix} }
}
class FakeResource {
  constructor(options) { this.options = options }
  dispose() { this.disposed = true }
}
const fakeThree = {
  Object3D: FakeObject3D, Vector3: FakeVector3,
  ConeGeometry: FakeResource, MeshBasicMaterial: FakeResource,
  InstancedMesh: FakeInstancedMesh, AdditiveBlending: 2,
  DynamicDrawUsage: 35048,
}
const visual = () => ({
  base: {body_id: "earth"},
  station: {visible: true, position: {...station}, scale: {x: 1}},
  planet: {activeId: "earth", group: {
    visible: true, position: {...planet}, scale: {x: 400},
  }},
  view: {body_id: "earth", stage: "orbital_preview"},
  camera: {position: {x: 0, y: 0, z: 0}},
})

test("reuses a bounded two-mesh pool and never creates targetable ship entities", () => {
  const scene = {
    children: [], add(node) {this.children.push(node)},
    remove(node) {this.children = this.children.filter(n => n !== node)},
  }
  const traffic = new AmbientRefineryTraffic(fakeThree, scene)
  const args = visual()
  traffic.update(args.base, args.station, args.planet, args.view, 4000, args.camera)
  assert.equal(scene.children.length, 2)
  assert.deepEqual(scene.children.map(n => n.count), [10, 10])
  assert.ok(scene.children.every(n => n.instanceMatrix.needsUpdate))
  assert.ok(scene.children.every(n => n.frustumCulled === false))
  assert.ok(scene.children.every(n => n.instances.length === 10))
  const before = scene.children.slice()
  const previousPosition = before[0].instances[0]
  traffic.update(args.base, args.station, args.planet, args.view, 8000, args.camera)
  assert.deepEqual(scene.children, before)
  assert.notDeepEqual(before[0].instances[0], previousPosition)
  // It never adds any entry to a game entity map, selectable array or socket.
  traffic.update(args.base, args.station, args.planet,
    {...args.view, body_id: "mars"}, 9000, args.camera)
  assert.ok(scene.children.every(n => n.visible === false))
  traffic.update(args.base, args.station, args.planet, args.view, 10000, args.camera)
  assert.ok(scene.children.every(n => n.visible))
  const materials = before.map(n => n.material)
  const geom = before[0].geometry
  traffic.dispose()
  assert.equal(scene.children.length, 0)
  assert.ok(materials.every(m => m.disposed))
  assert.ok(geom.disposed)
})

test("no traffic in Atlas cruise or when planet/station rendering is unavailable", () => {
  const scene = {children: [], add(node) {this.children.push(node)}, remove() {}}
  const traffic = new AmbientRefineryTraffic(fakeThree, scene)
  const data = visual()
  traffic.update(data.base, data.station, data.planet,
    {...data.view, stage: "approach_preview"}, 0, data.camera)
  assert.equal(scene.children.length, 0)
  traffic.update(data.base, {...data.station, visible: false},
    data.planet, data.view, 0, data.camera)
  assert.equal(scene.children.length, 0)
  traffic.update(data.base, data.station, {...data.planet, activeId: "venus"},
    data.view, 0, data.camera)
  assert.equal(scene.children.length, 0)
})
