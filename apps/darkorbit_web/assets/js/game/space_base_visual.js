import {spaceBasePose, spaceBaseProjection} from "./space_base_view.mjs"

// Original low-poly orbital logistics hub. No textures, animation loop,
// dynamic lights or new asset downloads: one mesh shared by laptop and HMD.
export class SpaceBaseVisual {
  constructor(THREE, scene) {
    this.THREE = THREE
    this.scene = scene
    this.node = null
    this.id = null
  }

  create() {
    const T = this.THREE
    const hull = new T.MeshStandardMaterial({
      color: 0x6a8395, metalness: 0.7, roughness: 0.42,
    })
    const dock = new T.MeshStandardMaterial({
      color: 0x2f8ba0, emissive: 0x083c48, metalness: 0.4,
    })
    const beacon = new T.MeshBasicMaterial({color: 0x8af3ff})
    const refinery = new T.MeshStandardMaterial({
      color: 0xb28f64, metalness: 0.55, roughness: 0.55,
    })
    const group = new T.Group()

    const ring = new T.Mesh(new T.TorusGeometry(19, 2.0, 8, 44), hull)
    ring.rotation.x = Math.PI / 2
    group.add(ring)

    const core = new T.Mesh(new T.CylinderGeometry(6, 8, 13, 10), hull)
    group.add(core)
    const stationAxis = new T.Mesh(new T.CylinderGeometry(1.4, 1.4, 43, 8), dock)
    group.add(stationAxis)

    for (let bay = 0; bay < 3; bay++) {
      const theta = bay * Math.PI * 2 / 3
      const x = Math.cos(theta) * 19
      const z = Math.sin(theta) * 19
      const pad = new T.Mesh(new T.BoxGeometry(10, 3, 11), dock)
      pad.position.set(x, 0, z)
      pad.rotation.y = -theta
      group.add(pad)

      const lamp = new T.Mesh(new T.SphereGeometry(1.2, 8, 6), beacon)
      lamp.position.set(x * 1.12, 2.6, z * 1.12)
      group.add(lamp)
    }

    const tower = new T.Mesh(new T.CylinderGeometry(5.5, 4.8, 18, 10), refinery)
    tower.position.y = -19
    group.add(tower)
    for (const z of [-7, 7]) {
      const tank = new T.Mesh(new T.CylinderGeometry(3.2, 3.2, 17, 8), refinery)
      tank.position.set(0, -21, z)
      group.add(tank)
    }

    this.scene.add(group)
    return group
  }

  update(source, camera) {
    const pose = spaceBasePose(source)
    if (!pose) {
      if (this.node) this.node.visible = false
      return
    }
    if (!this.node) this.node = this.create()
    const projected = spaceBaseProjection(pose, camera.position)
    if (!projected) {
      this.node.visible = false
      return
    }
    this.node.visible = true
    this.node.position.set(projected.position.x,
      projected.position.y, projected.position.z)
    this.node.scale.setScalar(projected.scale)
    this.id = pose.id
  }
}
