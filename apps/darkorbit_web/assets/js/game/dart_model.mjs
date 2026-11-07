// Original low-poly geometry for the 1989 Space Rogue Dart-inspired fighter.
// The Sunracer manual describes an orange 12m pirate fighter with swept
// delta wings, sharply pointed nose and a tall dorsal fin.
// These are procedural Three.js meshes, NOT scanned/copy-pasted game assets.
//
// Coordinates are Three.js ship-local: -Z nose, +Y up, +Z engines.
export const DART_MODEL_ID = "dart"
export const isDartModelId = id => id === DART_MODEL_ID ||
  (typeof id === "string" && /^solar-dart-[1-9][0-9]*$/.test(id))

export const DART_HULL_POINTS = Object.freeze([
  [ 0.00,  0.02, -2.45], // nose
  [-2.05, -0.06,  1.28], // left wing tip
  [ 2.05, -0.06,  1.28], // right wing tip
  [ 0.00,  0.38, -0.65], // dorsal ridge
  [ 0.00,  0.24,  1.28], // back spine
  [ 0.00, -0.23, -2.43], // keel nose
  [-2.05, -0.21,  1.28], // lower left wing
  [ 2.05, -0.21,  1.28], // lower right wing
  [ 0.00, -0.23,  1.28], // keel aft
])

export const DART_HULL_FACES = Object.freeze([
  [0, 1, 3], [0, 3, 2], [3, 1, 4], [3, 4, 2], // angular upper shell
  [5, 8, 6], [5, 7, 8],                       // bottom
  [0, 5, 6], [0, 6, 1], [0, 2, 7], [0, 7, 5], // wing leading edges
  [1, 6, 8], [1, 8, 4], [4, 8, 7], [4, 7, 2], // tail surfaces
])

// Target heading is in map XY (+X east, +Y south). Model nose is -Z.
// An angle of -90° (north) therefore leaves the Dart at zero rotation.
export const dartHeadingRotation = angle => -angle - Math.PI / 2

const shell = (THREE, points, faces, material) => {
  const vertices = faces.flatMap(face => face.flatMap(index => points[index]))
  const geometry = new THREE.BufferGeometry()
  geometry.setAttribute("position", new THREE.Float32BufferAttribute(vertices, 3))
  geometry.computeVertexNormals()
  return new THREE.Mesh(geometry, material)
}

const metal = (THREE, color, intensity = 0.07) => new THREE.MeshStandardMaterial({
  color, metalness: 0.62, roughness: 0.45,
  emissive: color, emissiveIntensity: intensity, side: THREE.DoubleSide,
})

export function createDartModel(THREE) {
  const root = new THREE.Group()
  root.name = "Dart pirate fighter"
  root.userData.modelId = DART_MODEL_ID

  const orange = metal(THREE, 0xd8742a)
  const accent = metal(THREE, 0x9e471d)
  const trim = metal(THREE, 0x554a45)
  const glass = metal(THREE, 0x101e32)
  const exhaust = new THREE.MeshBasicMaterial({color: 0x85deff})

  root.add(shell(THREE, DART_HULL_POINTS, DART_HULL_FACES, orange))

  // Raised central fuselage and black slit-like canopy under the fin.
  const fuselage = new THREE.Mesh(new THREE.BoxGeometry(0.72, 0.30, 2.1), accent)
  fuselage.position.set(0, 0.28, 0.03)
  root.add(fuselage)

  const canopy = new THREE.Mesh(new THREE.BoxGeometry(0.58, 0.10, 0.88), glass)
  canopy.position.set(0, 0.47, -0.63)
  canopy.rotation.x = -0.12
  root.add(canopy)

  // Tall swept rear dorsal fin from the original recognition silhouette.
  const finPoints = [
    [-0.065, 0.39, -0.14], [0.065, 0.39, -0.14],
    [-0.065, 0.36,  1.18], [0.065, 0.36,  1.18],
    [0.0, 1.65, 1.05],
  ]
  root.add(shell(THREE, finPoints, [
    [0, 2, 4], [1, 4, 3], [0, 4, 1], [2, 3, 4],
  ], accent))

  // Two rear exhaust ports, tapered engine housings and lit nozzles.
  for (const x of [-0.51, 0.51]) {
    const engine = new THREE.Mesh(new THREE.CylinderGeometry(0.22, 0.26, 0.6, 8), trim)
    engine.rotation.x = Math.PI / 2
    engine.position.set(x, -0.06, 1.12)
    root.add(engine)

    const glow = new THREE.Mesh(new THREE.CircleGeometry(0.17, 12), exhaust)
    glow.position.set(x, -0.06, 1.45)
    root.add(glow)
  }

  // Dark wing markings add silhouette detail without extra textures.
  for (const sign of [-1, 1]) {
    const stripe = new THREE.Mesh(new THREE.BoxGeometry(0.42, 0.035, 0.38), trim)
    stripe.position.set(sign * 1.16, -0.018, 0.78)
    stripe.rotation.y = sign * 0.26
    root.add(stripe)
  }

  // Retain the game's existing target-selection marker contract.
  const ring = new THREE.Mesh(
    new THREE.TorusGeometry(3.2, 0.085, 5, 48),
    new THREE.MeshBasicMaterial({color: 0xffa765}),
  )
  ring.position.y = -1.25
  ring.rotation.x = -Math.PI / 2
  ring.visible = false
  root.add(ring)
  root.userData.ring = ring

  return root
}
