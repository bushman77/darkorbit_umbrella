import {encounterRenderSpec} from "./encounter_visual.mjs"

// Only a visual sensor contact. It cannot be targeted, shot, boarded or
// collided with until a separate authoritative tactical handoff exists.
export class EncounterShipVisual {
  constructor(THREE, scene) {
    this.T = THREE
    this.scene = scene
    this.group = null
    this.id = null
  }

  build() {
    const T = this.T
    const g = new T.Group()
    const hullMaterial = new T.MeshStandardMaterial({
      color: 0xa4b8c7, metalness: 0.65, roughness: 0.38,
    })
    const dark = new T.MeshStandardMaterial({color: 0x334e65, metalness: 0.45})
    const hull = new T.Mesh(new T.CylinderGeometry(2.0, 2.7, 12, 10), hullMaterial)
    hull.rotation.x = Math.PI / 2
    g.add(hull)
    const wing = new T.Mesh(new T.BoxGeometry(13, 0.5, 4), dark)
    wing.position.z = 0.8
    g.add(wing)
    const bridge = new T.Mesh(new T.BoxGeometry(3.4, 2.4, 4), hullMaterial)
    bridge.position.set(0, 1.8, -2)
    g.add(bridge)
    const glow = new T.Mesh(
      new T.TorusGeometry(7.5, 0.055, 6, 64),
      new T.MeshBasicMaterial({color: 0x75e2ff, transparent: true, opacity: 0.55,
        depthWrite: false}),
    )
    g.add(glow)
    return g
  }

  update(navigation, camera) {
    const spec = encounterRenderSpec(navigation)
    if (!spec) {
      if (this.group) this.group.visible = false
      return null
    }
    if (!this.group) {
      this.group = this.build()
      this.scene.add(this.group)
    }
    this.id = spec.id
    this.group.visible = true
    const offset = new this.T.Vector3(spec.position.x, spec.position.y, spec.position.z)
      .applyQuaternion(camera.quaternion)
    this.group.position.copy(camera.position).add(offset)
    this.group.quaternion.copy(camera.quaternion)
    this.group.scale.setScalar(spec.scale)
    return spec
  }

  dispose() {
    if (!this.group) return
    this.scene.remove(this.group)
    this.group.traverse(obj => {
      obj.geometry?.dispose()
      const mats = Array.isArray(obj.material) ? obj.material : [obj.material]
      for (const mat of mats) mat?.dispose()
    })
    this.group = null
    this.id = null
  }
}
