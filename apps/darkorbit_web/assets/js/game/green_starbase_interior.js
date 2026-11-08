import {greenStarbaseInteriorVisible} from "./green_starbase_interior_state.mjs"

// A completely local, lightweight station interior for desktop and Android
// SBS. Rendering it never moves the authoritative ship or issues a station
// command. The same physical room is drawn in both stereo eye cameras.
export class GreenStarbaseInterior {
  constructor(THREE, scene) {
    this.scene = scene
    this.THREE = THREE
    this.materials = []
    this.geometries = []
    this.build()
  }

  build() {
    const T = this.THREE
    const group = new T.Group()
    group.name = "Green Starbase / secure docking hangar"
    group.userData.nonInteractive = true
    this.node = group
    this.scene.add(group)

    const material = (color, emissive = null) => {
      const m = emissive === null
        ? new T.MeshStandardMaterial({color, roughness: 0.82, metalness: 0.22,
          flatShading: true})
        : new T.MeshBasicMaterial({color: emissive})
      this.materials.push(m)
      return m
    }
    const steel = material(0x122d2a)
    const decking = material(0x183e35)
    const bulkhead = material(0x071c19)
    const supports = material(0x1c7351)
    const rail = material(0x64b56f)
    const light = material(0x76ffb0, 0x76ffb0)
    const amber = material(0xffc46b, 0xffc46b)
    const glass = material(0x092b28, 0x0e5142)

    const add = (geometry, surface, x, y, z, rotation = null) => {
      this.geometries.push(geometry)
      const mesh = new T.Mesh(geometry, surface)
      mesh.position.set(x, y, z)
      if (rotation) mesh.rotation.set(...rotation)
      group.add(mesh)
      return mesh
    }
    const box = (size, surface, position) =>
      add(new T.BoxGeometry(...size), surface, ...position)

    // Long, walkable hangar. The near wall is deliberately absent, looking
    // through the open hangar entrance toward the ship and service bulkhead.
    box([84, 2, 156], decking, [0, -5.5, -8])
    box([84, 3, 156], steel, [0, 33, -8])
    box([3, 39, 156], bulkhead, [-42, 13, -8])
    box([3, 39, 156], bulkhead, [42, 13, -8])
    box([84, 39, 3], steel, [0, 13, -85])

    // Recessed landing pad with server-owned ship represented by the berth,
    // not by a second pretend ship actor or client-controlled coordinates.
    box([45, 0.3, 60], steel, [0, -4.15, -19])
    for (const x of [-23, 23]) {
      box([1.1, 0.24, 62], light, [x, -3.90, -19])
      box([2.2, 7, 8], supports, [x, -0.6, -43])
      box([1.4, 1.0, 7], amber, [x * 0.91, 2.6, -43])
    }
    for (const z of [-48, -15, 13]) {
      box([43, 0.22, 1], light, [0, -3.91, z])
    }

    // Repeating structural ribs and ceiling guidance strips. Geometry is
    // static and small; nothing is streamed from the Phoenix server.
    for (const z of [-74, -38, -2, 34, 62]) {
      for (const x of [-39, 39]) {
        box([3, 34, 4], supports, [x, 12, z])
        box([0.8, 23, 0.4], light, [x * 0.94, 13, z - 2.2])
      }
      box([80, 2, 3], supports, [0, 29, z])
      for (const x of [-21, 0, 21]) {
        box([12, 0.25, 1.1], light, [x, 27.9, z])
      }
    }

    // Raised port/starboard service walks and machine consoles.
    for (const side of [-1, 1]) {
      box([11, 1.8, 136], decking, [side * 35, -2.6, -7])
      box([0.8, 2.8, 136], rail, [side * 28, -0.4, -7])
      for (const z of [-62, -37, 6, 28]) {
        box([7, 5, 6], supports, [side * 34, 0.6, z])
        box([5.8, 3.5, 0.24], glass, [side * 34, 1.0, z + 3.1])
        box([5.8, 0.25, 0.5], amber, [side * 34, 3.2, z + 3.4])
      }
    }

    // Secured services airlock at the end of the hangar. Station services
    // remain desktop-controlled; panels are not fabricated trade screens.
    box([31, 24, 0.8], bulkhead, [0, 7.5, -83.1])
    box([16, 19, 0.7], glass, [0, 4, -82.6])
    for (const x of [-9, 9]) {
      box([1.1, 23, 0.9], light, [x, 6.6, -82.1])
    }
    box([21, 1.2, 1], light, [0, 18, -82])
    box([27, 4, 2], supports, [0, 28, -82])

    // In-world light sources illuminate surfaces from either SBS eye.
    this.scene.add(new T.HemisphereLight(0x79ffd2, 0x040b0c, 2.4))
    const overhead = new T.DirectionalLight(0x8dffb1, 2.3)
    overhead.position.set(-12, 28, 17)
    this.scene.add(overhead)
  }

  dispose() {
    this.scene.remove(this.node)
    this.geometries.forEach(geometry => geometry.dispose())
    this.materials.forEach(material => material.dispose())
    this.geometries = []
    this.materials = []
  }
}

export {greenStarbaseInteriorVisible}
