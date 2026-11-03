import {planetaryRenderSpec, PLANET_APPEARANCE, generatePlanetPixels} from "./planetary_view.mjs"

// A camera-relative *draw layer*, NOT a planet-sized scene or collision mesh.
// The same fixed scene depth works in normal 3D and in SBS, while the sphere
// radius is computed from the authoritative angular size for this pilot.
// A planet's direction is anchored in the local sector on first acquisition:
// turning the ship can move it out of view, unlike a HUD billboard.
export class PlanetaryBody {
  constructor(THREE, scene) {
    this.THREE = THREE
    this.scene = scene
    this.activeId = null
    this.anchor = null
    this.group = null
    this.clouds = null
  }

  create(id) {
    const T = this.THREE
    const data = generatePlanetPixels(id)
    if (!data) return null
    const canvas = document.createElement("canvas")
    canvas.width = data.width
    canvas.height = data.height
    const context = canvas.getContext("2d")
    if (!context) return null
    const image = context.createImageData(data.width, data.height)
    image.data.set(data.pixels)
    context.putImageData(image, 0, 0)

    const texture = new T.CanvasTexture(canvas)
    texture.colorSpace = T.SRGBColorSpace
    texture.wrapS = T.RepeatWrapping
    texture.anisotropy = 2

    const group = new T.Group()
    const sphere = new T.Mesh(
      new T.SphereGeometry(1, 64, 48),
      new T.MeshStandardMaterial({
        map: texture,
        roughness: 1.0,
        metalness: 0,
        emissive: new T.Color(0x151007),
        emissiveIntensity: 0.14,
      }),
    )
    sphere.renderOrder = -10
    group.add(sphere)

    const atmosphere = new T.Mesh(
      new T.SphereGeometry(1.035, 64, 40),
      new T.MeshBasicMaterial({
        color: PLANET_APPEARANCE[id].haze,
        transparent: true,
        opacity: 0.22,
        side: T.BackSide,
        blending: T.AdditiveBlending,
        depthWrite: false,
      }),
    )
    atmosphere.renderOrder = -9
    group.add(atmosphere)
    this.clouds = sphere
    this.scene.add(group)
    return group
  }

  dispose() {
    if (!this.group) return
    this.scene.remove(this.group)
    this.group.traverse(child => {
      child.geometry?.dispose()
      const materials = Array.isArray(child.material) ? child.material : [child.material]
      for (const material of materials) {
        material?.map?.dispose()
        material?.dispose()
      }
    })
    this.group = null
    this.clouds = null
  }

  update(navigation, camera, time = 0) {
    const spec = planetaryRenderSpec(navigation?.planetary_view)
    if (!spec) {
      if (this.group) this.group.visible = false
      return null
    }

    if (spec.id !== this.activeId || !this.group) {
      this.dispose()
      this.group = this.create(spec.id)
      this.activeId = this.group ? spec.id : null
      // First acquisition is centered on the current helm bearing. Keep
      // the vector fixed in world-space while yawing/pitching afterward.
      this.anchor = new this.THREE.Vector3(0, 0, -1)
        .applyQuaternion(camera.quaternion).normalize()
    }

    if (!this.group) return null
    this.group.visible = true
    this.group.position.copy(camera.position).addScaledVector(this.anchor, spec.sceneDistance)
    this.group.scale.setScalar(spec.sceneRadius)
    // Extremely slow aesthetic cloud rotation; not orbital physics.
    if (this.clouds) this.clouds.rotation.y = (time % 12_000_000) * 0.00000006
    return spec
  }
}
