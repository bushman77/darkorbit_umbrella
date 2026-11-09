import test from "node:test"
import assert from "node:assert/strict"
import * as THREE from "three"
import {GreenStarbaseInterior} from "./green_starbase_interior.js"
import {
  STATION_CHARACTER_ASSETS, positionStationCharacter, disposeStationCharacter,
} from "./station_character_models.mjs"

const mara = {
  id: "repair", x: -49, z: -143, name: "Mara Venn",
  role: "Repair Engineer", color: 0x68b98a,
}

const meshGltf = () => {
  const scene = new THREE.Group()
  const body = new THREE.Mesh(
    new THREE.BoxGeometry(0.65, 1.75, 0.45),
    new THREE.MeshStandardMaterial({color: 0x438863}),
  )
  body.position.y = 0.875
  scene.add(body)
  return {scene}
}

test("Blender metre-scale GLB is centered, feet-grounded, and faces the repair counter", () => {
  const gltf = meshGltf()
  const model = positionStationCharacter(THREE, gltf, mara)
  const bounds = new THREE.Box3().setFromObject(model)
  assert.equal(model.name, "station-character:repair")
  assert.equal(model.userData.nonInteractive, true)
  assert.equal(model.position.x, mara.x)
  assert.equal(model.position.z, mara.z)
  assert.ok(Math.abs(bounds.min.y - (-4.65)) < 0.001)
  assert.ok(Math.abs((bounds.max.y - bounds.min.y) - 8.5) < 0.001)
  assert.equal(model.rotation.y, 0)
  disposeStationCharacter(model)
})

test("Green Starbase swaps Mara's visual and keeps all attendant interactions", async () => {
  const scene = new THREE.Scene()
  let requested = null
  let resolveModel
  const room = new GreenStarbaseInterior(THREE, scene, {
    lowPower: true,
    loadGltf(url) {
      requested = url
      return new Promise(resolve => {resolveModel = resolve})
    },
  })
  const trader = {...mara, id: "trade", x: 49, name: "Tarek Sol"}
  room.update({x: 0, z: 43}, 100, [mara, trader])
  await Promise.resolve() // Request starts on a microtask, never per frame.
  assert.equal(requested, STATION_CHARACTER_ASSETS.repair)
  resolveModel(meshGltf())
  await new Promise(resolve => setImmediate(resolve))
  const imported = room.node.children.find(o => o.name === "station-character:repair")
  assert.ok(imported, "Mara's Blender model is attached to the shared scene")
  assert.ok(room.node.children.filter(o =>
    o.name?.startsWith("attendant:repair:")).every(o => o.visible === false))
  assert.ok(room.node.children.filter(o =>
    o.name?.startsWith("attendant:trade:")).every(o => o.visible !== false))
  const count = room.node.children.length
  room.update({x: 0, z: 43}, 200, [mara, trader])
  assert.equal(room.node.children.length, count, "no per-frame model rebuilding")
  room.dispose()
  assert.equal(scene.children.includes(room.node), false)
})

test("a missing Blender model retains the procedural repair engineer", async () => {
  const scene = new THREE.Scene()
  let calls = 0
  const originalInfo = console.info
  console.info = () => {}
  try {
    const room = new GreenStarbaseInterior(THREE, scene, {
      lowPower: true,
      loadGltf() {
        calls++
        return Promise.reject(new Error("GLB not yet exported"))
      },
    })
    room.update({x: 0, z: 43}, 100, [mara])
    await new Promise(resolve => setImmediate(resolve))
    room.update({x: 0, z: 43}, 200, [mara])
    assert.equal(calls, 1, "a missing asset must not be fetched every frame")
    assert.ok(room.node.children.some(o =>
      o.name === "attendant:repair:torso" && o.visible !== false))
    room.dispose()
  } finally {
    console.info = originalInfo
  }
})
