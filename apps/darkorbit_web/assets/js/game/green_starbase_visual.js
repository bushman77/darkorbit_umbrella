import {toScene} from "./stereo_math.mjs"

// Original green, early-3D polygonal design language: opposing pyramids,
// industrial connecting block, and a real open docking aperture.
// Rendering only. Server docking/physics remains a separate milestone.
const ID = "sol:starbase:green"

export function starbaseVisible(navigation, mapId) {
  if (!mapId?.startsWith("sol:free_") ||
      navigation?.status !== "idle" || navigation.location_id !== null ||
      navigation.green_starbase_nearby !== true) return false
  return navigation.starbases?.some(base => base.id === ID &&
    base.model === "green_pyramid_starbase_v1") || false
}

export class GreenStarbaseVisual {
  constructor(THREE, scene) {
    this.THREE = THREE
    this.scene = scene
    this.node = null
    this.materials = []
    this.geometries = []
  }

  build(site) {
    if (this.node) return
    const T = this.THREE
    const node = new T.Group()
    node.name = "Green Starbase · SOL independent station"
    node.userData.nonInteractive = true
    const main = new T.MeshStandardMaterial({
      color: 0x17c947, metalness: 0.15, roughness: 0.78, flatShading: true,
    })
    const shade = new T.MeshStandardMaterial({
      color: 0x075524, metalness: 0.14, roughness: 0.81, flatShading: true,
    })
    const trim = new T.MeshStandardMaterial({
      color: 0x35f05b, metalness: 0.10, roughness: 0.76, flatShading: true,
    })
    const interior = new T.MeshBasicMaterial({color: 0x02190f})
    const neon = new T.MeshBasicMaterial({color: 0xb9ff6c})
    this.materials = [main, shade, trim, interior, neon]
    const add = (geometry, material, pos, rotation = null) => {
      this.geometries.push(geometry)
      const mesh = new T.Mesh(geometry, material)
      mesh.position.set(...pos)
      if (rotation) mesh.rotation.set(...rotation)
      node.add(mesh)
      return mesh
    }

    // The two diamond points recall the unmistakable original silhouette.
    // Four polygons per pyramid and a broad block keep a retro aesthetic.
    add(new T.ConeGeometry(35, 42, 4), main, [0, 30, 0],
      [0, Math.PI / 4, 0])
    add(new T.ConeGeometry(35, 42, 4), shade, [0, -30, 0],
      [0, Math.PI / 4, Math.PI])

    // Hollow middle: the front (-Z) is an opening, not a painted polygon.
    add(new T.BoxGeometry(12, 20, 48), main, [-28, 0, 0])
    add(new T.BoxGeometry(12, 20, 48), main, [28, 0, 0])
    add(new T.BoxGeometry(44, 4, 48), trim, [0, 12, 0])
    add(new T.BoxGeometry(44, 4, 48), shade, [0, -12, 0])
    add(new T.BoxGeometry(44, 2, 45), shade, [0, -9, 0])
    add(new T.BoxGeometry(44, 18, 1), interior, [0, 0, 23.5])

    // The four illuminated edges lead the pilot into the open central bay.
    for (const x of [-21, 21]) {
      add(new T.BoxGeometry(1.3, 21, 0.8), neon, [x, 0, -24.2])
    }
    for (const y of [-10.8, 10.8]) {
      add(new T.BoxGeometry(43, 1.3, 0.8), neon, [0, y, -24.2])
    }
    // Industrial corner braces, windows and a pair of simple aerials.
    for (const side of [-1, 1]) {
      add(new T.BoxGeometry(7, 23, 53), shade, [side * 36, 0, 0])
      add(new T.BoxGeometry(10, 6, 10), trim, [side * 29, 15, 5])
      add(new T.CylinderGeometry(0.85, 0.85, 10, 5), trim,
        [side * 29, 23, 5])
      for (let n = 0; n < 4; n++) {
        add(new T.BoxGeometry(2.5, 1.7, 0.5), neon,
          [side * (23 + n * 5), 1, -27])
      }
    }
    const position = toScene(site)
    node.position.set(position.x, position.y, position.z)
    node.visible = false
    this.node = node
    this.scene.add(node)
  }

  update(navigation, mapId) {
    const active = starbaseVisible(navigation, mapId)
    if (active && !this.node) {
      const base = navigation.starbases.find(b => b.id === ID)
      const site = base.site_3d
      if (!site || ![site.x, site.y, site.z].every(Number.isFinite)) return
      this.build(site)
    }
    if (this.node) this.node.visible = active
  }

  dispose() {
    if (this.node) this.scene.remove(this.node)
    this.materials.forEach(m => m.dispose())
    this.geometries.forEach(g => g.dispose())
    this.node = null
    this.materials = []
    this.geometries = []
  }
}
