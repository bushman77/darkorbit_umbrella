import test from "node:test"
import assert from "node:assert/strict"
import {GreenStarbaseInterior} from "./green_starbase_interior.js"
import {greenStarbaseInteriorVisible, pilotDockedInWorld} from
  "./green_starbase_interior_state.mjs"

test("only a server-confirmed docked pilot in Green Starbase's own region enters the hangar", () => {
  const map = {map_id: "sol:free_15", docked_pilots: [15, 26]}
  assert.equal(pilotDockedInWorld(map, "15"), true)
  assert.equal(pilotDockedInWorld(map, "18"), false)
  assert.equal(pilotDockedInWorld({...map, docked_pilots: []}, "15"), false)
  assert.equal(pilotDockedInWorld({...map, map_id: "sol:earth"}, "15"), false)
  assert.equal(pilotDockedInWorld({...map, map_id: "1-1"}, "15"), false)
  assert.equal(pilotDockedInWorld({...map, map_id: "sol:free_0"}, "15"), false)
  assert.equal(pilotDockedInWorld(null, "15"), false)
  assert.equal(greenStarbaseInteriorVisible({docked: true, mapId: "sol:free_15"}), true)
  assert.equal(greenStarbaseInteriorVisible({docked: false, mapId: "sol:free_15"}), false)
  assert.equal(greenStarbaseInteriorVisible({docked: true, mapId: "sol:earth"}), false)
  assert.equal(greenStarbaseInteriorVisible({docked: true, mapId: null}), false)
})

class Group {
  constructor() {this.children = []; this.userData = {}}
  add(obj) {this.children.push(obj)}
}
class Mesh {
  constructor(geometry, material) {
    this.geometry = geometry; this.material = material
    this.position = {set: (...parts) => {this.at = parts}}
    this.rotation = {set: (...parts) => {this.angles = parts}}
  }
}
class Resource {
  constructor(...args) {this.args = args}
  dispose() {this.disposed = true}
}
class Light {
  constructor(...args) {
    this.args = args; this.position = {set: (...parts) => {this.at = parts}}
  }
}
const THREE = {
  Group, Mesh, BoxGeometry: Resource, MeshStandardMaterial: Resource,
  MeshBasicMaterial: Resource, HemisphereLight: Light, DirectionalLight: Light,
}
test("one local static SBS hangar has an open flight entrance, station surfaces and safe disposal", () => {
  const scene = {children: [], add(obj) {this.children.push(obj)},
    remove(obj) {this.children = this.children.filter(child => child !== obj)}}
  const room = new GreenStarbaseInterior(THREE, scene)
  assert.equal(scene.children.includes(room.node), true)
  assert.equal(room.node.userData.nonInteractive, true)
  assert.ok(room.node.children.length > 45)
  assert.ok(room.geometries.some(g => g.args[0] === 84 && g.args[2] === 156))
  assert.ok(room.materials.length >= 7)
  assert.equal(room.node.children.every(child => child instanceof Mesh), true)
  const geometry = room.geometries[0]
  const material = room.materials[0]
  room.dispose()
  assert.equal(scene.children.includes(room.node), false)
  assert.equal(geometry.disposed, true)
  assert.equal(material.disposed, true)
})

test("the actual rear door slides aside when a docked pilot approaches", () => {
  const scene = {children: [], add(node) {this.children.push(node)},
    remove(node) {this.children = this.children.filter(n => n !== node)}}
  const station = new GreenStarbaseInterior(THREE, scene)
  const left = station.doorLeft
  const right = station.doorRight
  station.update({room_id: "main_hangar", x: 0, z: -75}, 100)
  station.update({room_id: "main_hangar", x: 0, z: -75}, 200)
  assert.ok(left.at[0] < -3.95)
  assert.ok(right.at[0] > 3.95)
  station.update({room_id: "concourse", x: 0, z: -150}, 300)
  assert.ok(station.doorOpen < 1)
  station.dispose()
})

test("the concourse and six service rooms are built locally without streaming assets", () => {
  const scene = {children: [], add(node) {this.children.push(node)},
    remove(node) {this.children = this.children.filter(n => n !== node)}}
  const station = new GreenStarbaseInterior(THREE, scene)
  const surfaces = station.geometries.map(g => g.args)
  assert.ok(surfaces.some(a => a[0] === 70 && a[2] === 84))
  assert.ok(surfaces.some(a => a[0] === 28 && a[2] === 34))
  assert.ok(surfaces.some(a => a[0] === 24 && a[2] === 27))
  assert.equal(station.lights.length, 2)
  station.dispose()
  assert.equal(station.lights.length, 0)
})
