import assert from "node:assert/strict"
import test from "node:test"
import {PlanetaryBody} from "./planetary_body.js"

class Vector3 {
  constructor(x = 0, y = 0, z = 0) { this.x = x; this.y = y; this.z = z }
  applyQuaternion(q) {
    // Sufficient normalized quaternion rotation for fixed-direction checks.
    const x = this.x, y = this.y, z = this.z
    const tx = 2 * (q.y * z - q.z * y)
    const ty = 2 * (q.z * x - q.x * z)
    const tz = 2 * (q.x * y - q.y * x)
    this.x = x + q.w * tx + q.y * tz - q.z * ty
    this.y = y + q.w * ty + q.z * tx - q.x * tz
    this.z = z + q.w * tz + q.x * ty - q.y * tx
    return this
  }
  normalize() { const d = Math.hypot(this.x, this.y, this.z); this.x /= d; this.y /= d; this.z /= d; return this }
  copy(v) { this.x = v.x; this.y = v.y; this.z = v.z; return this }
  addScaledVector(v, scale) { this.x += v.x * scale; this.y += v.y * scale; this.z += v.z * scale; return this }
}

class Group {
  constructor() {
    this.children = []
    this.position = new Vector3()
    this.scale = {value: 1, setScalar(value) { this.value = value }}
    this.visible = true
  }
  add(child) { this.children.push(child) }
  traverse(fn) { for (const child of this.children) fn(child) }
}

class Mesh {
  constructor(geometry, material) {
    this.geometry = geometry
    this.material = material
    this.rotation = {y: 0}
  }
}

class Geometry { dispose() { this.disposed = true } }
class Material {
  constructor(options) { Object.assign(this, options) }
  dispose() { this.disposed = true }
}

const THREE = {
  Group, Mesh, Vector3,
  SphereGeometry: Geometry,
  MeshStandardMaterial: Material,
  MeshBasicMaterial: Material,
  Color: class { constructor(value) { this.value = value } },
  CanvasTexture: class { constructor(canvas) { this.canvas = canvas } dispose() { this.disposed = true } },
  BackSide: 1, AdditiveBlending: 2, SRGBColorSpace: 3, RepeatWrapping: 4,
}

const snapshot = (id, degrees, stage = "orbital_preview") => ({
  planetary_view: {
    body_id: id, radius_km: 6051.8,
    visual_distance_km: 6051.8 / Math.sin(degrees * Math.PI / 360),
    angular_diameter_deg: degrees, stage, visual_only: true,
  },
})

const fakeCanvas = () => ({
  width: 0, height: 0,
  getContext: () => ({
    createImageData: (width, height) => ({data: new Uint8ClampedArray(width * height * 4)}),
    putImageData: () => {},
  }),
})

test("planet stays at a fixed world bearing while its size grows and camera changes", () => {
  const previous = globalThis.document
  globalThis.document = {createElement: () => fakeCanvas()}
  try {
    const scene = new Group()
    scene.remove = object => {scene.children = scene.children.filter(item => item !== object)}
    const body = new PlanetaryBody(THREE, scene)
    const camera = {
      position: new Vector3(10, 20, 30),
      quaternion: {x: 0, y: 0, z: 0, w: 1},
    }
    body.update(snapshot("venus", 1.5, "approach_preview"), camera, 2000)
    const startScale = body.group.scale.value
    assert.equal(body.group.position.z, -870)
    assert.equal(scene.children.length, 1)
    body.update(snapshot("venus", 65), camera, 4000)
    assert.ok(body.group.scale.value > startScale * 20)

    camera.position = new Vector3(20, 20, 40)
    camera.quaternion = {x: 0, y: 1, z: 0, w: 0}
    body.update(snapshot("venus", 65), camera, 5000)
    assert.equal(body.group.position.x, 20)
    assert.equal(body.group.position.z, -860)
    assert.equal(scene.children.length, 1)

    body.update(null, camera)
    assert.equal(body.group.visible, false)
    body.dispose()
    assert.equal(scene.children.length, 0)
  } finally {
    globalThis.document = previous
  }
})
