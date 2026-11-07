// Authoritative XYZ space. Game XY maps onto Three.js XZ; altitude Z maps to Three.js Y.
export const WORLD_SCALE = 0.06

export const toScene = ({x, y, z = 0}) => ({
  x: x * WORLD_SCALE, y: z * WORLD_SCALE, z: y * WORLD_SCALE,
})

export const toWorld = ({x, y = 0, z}) => ({
  x: x / WORLD_SCALE, y: z / WORLD_SCALE, z: y / WORLD_SCALE,
})

// Stereo coordinates are relative to the selected half of an SBS display.
export function pointerNdc(pointer, rect, mode = "3d") {
  if (!(rect?.width > 0) || !(rect?.height > 0)) return null
  let x = (pointer.clientX - rect.left) / rect.width
  const y = (pointer.clientY - rect.top) / rect.height
  if (![x, y].every(Number.isFinite) || x < 0 || x > 1 || y < 0 || y > 1) return null
  let eye = "center"
  if (mode === "sbs") {
    eye = x < 0.5 ? "left" : "right"
    x = eye === "left" ? x * 2 : (x - 0.5) * 2
  }
  return {x: x * 2 - 1, y: 1 - y * 2, eye}
}
