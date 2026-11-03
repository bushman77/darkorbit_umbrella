// Original, procedural low-poly civilian cargo vessel.
// Inspired by the *role* of the 1989 Space Rogue Scow, not copied game art.
// Local coordinates: -Z bow, +Z stern, +Y dorsal. Approx 1:1.9 length
// compared with the existing Dart fighter's schematic mesh.
export const SCOW_MODEL_ID = "scow"
export const SCOW_SPEC = Object.freeze({
  role: "merchant",
  lengthMetres: 23,
  cargoTonnes: 10,
  armor: 210,
  garnetLaser: 10,
  hasMissiles: false,
})

export const isScowModelId = id => id === SCOW_MODEL_ID ||
  (typeof id === "string" && /^solar-scow-[1-9][0-9]*$/.test(id))

// Geometry deliberately built from simple primitives so the same low-poly
// silhouette is rendered on the laptop and read-only SBS phone HMD.
export function createScowModel(THREE) {
  const ship = new THREE.Group()
  ship.name = "Scow light cargo trader"
  ship.userData.modelId = SCOW_MODEL_ID

  const metal = (hex, emissiveIntensity = 0.07) =>
    new THREE.MeshStandardMaterial({
      color: hex, metalness: 0.35, roughness: 0.62,
      emissive: hex, emissiveIntensity,
    })
  const hullMat = metal(0x315f93)
  const cargoMat = metal(0x7298b7)
  const frameMat = metal(0x1c3c61)
  const pipingMat = metal(0xb4cee1)
  const glazing = new THREE.MeshStandardMaterial({
    color: 0x081d38, metalness: 0.18, roughness: 0.12,
    emissive: 0x122c52, emissiveIntensity: 0.22,
  })
  const engineGlow = new THREE.MeshBasicMaterial({color: 0x8eeeff})

  // Rounded utility bow taper and long working hull.
  const body = new THREE.Mesh(new THREE.BoxGeometry(2.45, 1.1, 5.0), hullMat)
  body.position.z = 0.2
  ship.add(body)

  const bow = new THREE.Mesh(new THREE.SphereGeometry(1.0, 12, 8), hullMat)
  bow.scale.set(1.23, 0.55, 1.4)
  bow.position.z = -2.45
  ship.add(bow)

  const bridge = new THREE.Mesh(new THREE.BoxGeometry(1.46, 0.48, 1.3), cargoMat)
  bridge.position.set(0, 0.53, -1.95)
  ship.add(bridge)

  const windshield = new THREE.Mesh(new THREE.BoxGeometry(1.19, 0.27, 0.075), glazing)
  windshield.position.set(0, 0.65, -2.625)
  windshield.rotation.x = -0.28
  ship.add(windshield)

  // Wide, low rear cargo deck distinguishes the trader from swept-wing
  // fighter hulls. Four visible segmented load bays under structural ribs.
  const deck = new THREE.Mesh(new THREE.BoxGeometry(3.9, 0.25, 3.35), hullMat)
  deck.position.set(0, -0.13, 1.15)
  ship.add(deck)

  for (const side of [-1, 1]) {
    const wing = new THREE.Mesh(new THREE.BoxGeometry(1.32, 0.17, 2.62), frameMat)
    wing.position.set(side * 1.59, -0.17, 1.25)
    ship.add(wing)

    const rail = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.28, 2.45), pipingMat)
    rail.position.set(side * 1.92, 0.04, 1.21)
    ship.add(rail)
  }

  for (let i = 0; i < 4; i++) {
    const z = -0.18 + i * 0.72
    const container = new THREE.Mesh(new THREE.BoxGeometry(2.1, 0.78, 0.55), cargoMat)
    container.position.set(0, 0.67, z)
    ship.add(container)

    const rib = new THREE.Mesh(new THREE.BoxGeometry(2.44, 0.16, 0.1), pipingMat)
    rib.position.set(0, 1.1, z + 0.29)
    ship.add(rib)
  }

  const turret = new THREE.Mesh(new THREE.CylinderGeometry(0.29, 0.37, 0.25, 8), frameMat)
  turret.position.set(0, 1.15, -0.82)
  ship.add(turret)
  const beam = new THREE.Mesh(new THREE.CylinderGeometry(0.065, 0.075, 0.9, 6), pipingMat)
  beam.rotation.x = Math.PI / 2
  beam.position.set(0, 1.22, -1.18)
  ship.add(beam)

  // Two engine bells; the Scow has no missile weapons or fighter tail fin.
  for (const x of [-0.77, 0.77]) {
    const engine = new THREE.Mesh(new THREE.CylinderGeometry(0.34, 0.43, 0.65, 10), frameMat)
    engine.rotation.x = Math.PI / 2
    engine.position.set(x, -0.21, 2.83)
    ship.add(engine)

    const glow = new THREE.Mesh(new THREE.CircleGeometry(0.28, 12), engineGlow)
    glow.position.set(x, -0.21, 3.19)
    ship.add(glow)
  }

  const ring = new THREE.Mesh(
    new THREE.TorusGeometry(3.9, 0.085, 5, 48),
    new THREE.MeshBasicMaterial({color: 0xffce76}),
  )
  ring.position.y = -1.1
  ring.rotation.x = -Math.PI / 2
  ring.visible = false
  ship.add(ring)
  ship.userData.ring = ring
  return ship
}
