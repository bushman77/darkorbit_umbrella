// Visual-only character assets. Identity, proximity, dialogue and location
// always come from Core.World.StationAttendants via MapServer snapshots.
export const STATION_CHARACTER_ASSETS = Object.freeze({
  repair: "/images/game/station/mara_venn.glb",
})

// Blender exports metres; the station's procedural characters are ~9 local
// units high. Fit from the exported bounds instead of assuming Blender scale
// or origin. Mara's current Blender export already faces the repair kiosk
// visitors without an additional 180-degree yaw.
export function positionStationCharacter(THREE, gltf, npc, {
  floorY = -4.65, height = 8.5,
} = {}) {
  if (!gltf?.scene || !Number.isFinite(npc?.x) || !Number.isFinite(npc?.z)) {
    throw new Error("Invalid station character or GLB scene")
  }
  const root = gltf.scene
  root.updateMatrixWorld(true)
  const bounds = new THREE.Box3().setFromObject(root)
  const sizeY = bounds.max.y - bounds.min.y
  if (!Number.isFinite(sizeY) || sizeY <= 0 ||
      !Number.isFinite(bounds.min.x) || !Number.isFinite(bounds.max.x) ||
      !Number.isFinite(bounds.min.z) || !Number.isFinite(bounds.max.z)) {
    throw new Error("Station GLB has empty or invalid geometry")
  }
  const scale = height / sizeY
  const xMiddle = (bounds.min.x + bounds.max.x) / 2
  const zMiddle = (bounds.min.z + bounds.max.z) / 2
  const anchor = new THREE.Group()
  anchor.name = "station-character:" + npc.id
  anchor.userData.nonInteractive = true
  anchor.position.set(npc.x, floorY, npc.z)
  anchor.rotation.y = 0

  const fitted = new THREE.Group()
  fitted.scale.setScalar(scale)
  fitted.position.set(-xMiddle * scale, -bounds.min.y * scale, -zMiddle * scale)
  fitted.add(root)
  anchor.add(fitted)
  return anchor
}

// Release only imported GLB resources; the procedural station's shared
// materials and geometry belong to GreenStarbaseInterior.dispose().
export function disposeStationCharacter(root) {
  if (!root) return
  const geometries = new Set()
  const materials = new Set()
  const textures = new Set()
  root.traverse?.(node => {
    if (node.geometry) geometries.add(node.geometry)
    for (const material of (Array.isArray(node.material) ?
      node.material : node.material ? [node.material] : [])) {
      materials.add(material)
    }
  })
  for (const material of materials) {
    for (const value of Object.values(material)) {
      if (value && value.isTexture) textures.add(value)
    }
  }
  for (const geometry of geometries) geometry.dispose?.()
  for (const texture of textures) texture.dispose?.()
  for (const material of materials) material.dispose?.()
}
