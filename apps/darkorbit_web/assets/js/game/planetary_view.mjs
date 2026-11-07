// Planet visuals are projections, never collision geometry or player motion.
// All size and destination metadata must come from Core.Universe.PlanetaryView
// inside the authenticated solar navigation snapshot.
export const PLANET_APPEARANCE = Object.freeze({
  mercury: {base: [157, 148, 135], pale: [192, 184, 168], dark: [90, 85, 80], haze: 0xaeb2b4},
  venus:   {base: [219, 171, 112], pale: [250, 226, 181], dark: [161, 106, 66], haze: 0xf2c892},
  earth:   {base: [28, 82, 160], pale: [231, 243, 248], dark: [14, 45, 104], haze: 0x72b8ff},
  mars:    {base: [172, 90, 58], pale: [229, 162, 105], dark: [96, 49, 42], haze: 0xca765a},
  jupiter: {base: [183, 141, 105], pale: [239, 215, 180], dark: [133, 88, 73], haze: 0xd4ad92},
  saturn:  {base: [205, 183, 138], pale: [247, 226, 176], dark: [139, 113, 85], haze: 0xdfcfab},
  uranus:  {base: [121, 194, 201], pale: [194, 239, 231], dark: [75, 140, 165], haze: 0x9be7ea},
  neptune: {base: [55, 94, 184], pale: [127, 171, 239], dark: [28, 48, 120], haze: 0x527fee},
  pluto:   {base: [162, 139, 120], pale: [222, 195, 174], dark: [99, 86, 86], haze: 0xceb6aa},
})

// Existing SOL worlds retain their hand-tuned procedural palettes; newly
// registered planets receive a neutral procedural appearance automatically.
const GENERIC_PLANET_APPEARANCE = Object.freeze({
  base: [132, 149, 171], pale: [198, 213, 226],
  dark: [79, 94, 123], haze: 0x8fa8bd,
})

const validBodyId = id =>
  typeof id === "string" && /^[a-z][a-z0-9_-]{0,39}$/.test(id)

export function planetAppearance(id) {
  if (!validBodyId(id)) return null
  return Object.hasOwn(PLANET_APPEARANCE, id)
    ? PLANET_APPEARANCE[id]
    : GENERIC_PLANET_APPEARANCE
}

const finitePositive = x => Number.isFinite(x) && x > 0

export function planetaryRenderSpec(view, sceneDistance = 900) {
  if (!view || view.visual_only !== true || !validBodyId(view.body_id) ||
      !["approach_preview", "orbital_preview"].includes(view.stage) ||
      !finitePositive(view.radius_km) || !finitePositive(view.visual_distance_km) ||
      !finitePositive(view.angular_diameter_deg) || !finitePositive(sceneDistance)) return null

  const ratio = view.radius_km / view.visual_distance_km
  if (!(ratio > 0 && ratio < 0.92)) return null
  const apparentDiameter = 2 * Math.asin(ratio) * 180 / Math.PI
  // Reject internally contradictory sizing; the client must not invent scale.
  if (Math.abs(apparentDiameter - view.angular_diameter_deg) > 0.15) return null

  return {
    id: view.body_id,
    stage: view.stage,
    angularDiameterDeg: apparentDiameter,
    sceneDistance,
    sceneRadius: sceneDistance * ratio,
  }
}

// A canvas-generated, deterministic texture: no external network requests,
// no high-resolution asset downloads, and no GPU shaders required on the
// laptop or paired phone. Visual only, not geographically accurate terrain.
export function generatePlanetPixels(id, width = 512, height = 256) {
  const palette = planetAppearance(id)
  if (!palette || !Number.isInteger(width) || !Number.isInteger(height) ||
      width < 2 || height < 2 || width > 2048 || height > 1024) return null
  const pixels = new Uint8ClampedArray(width * height * 4)
  const mix = (a, b, t) => a * (1 - t) + b * t
  const clamp = x => Math.min(1, Math.max(0, x))
  for (let y = 0; y < height; y++) {
    const v = y / height
    const latitude = (v - 0.5) * Math.PI
    const pole = Math.abs(Math.cos(latitude))
    for (let x = 0; x < width; x++) {
      const u = x / width
      const longitude = u * Math.PI * 2
      const warp = Math.sin(longitude * 5 + Math.sin(latitude * 4)) * 1.5 +
        Math.sin(longitude * 9 - latitude * 3) * 0.62
      const bands = Math.sin(latitude * 20 + warp * 1.8)
      const threads = Math.sin(latitude * 53 + longitude * 7 + warp * 2.7)
      const waves = Math.cos(longitude * 16 + latitude * 9 + warp * 3.5)
      const turbulence = 0.5 + 0.24 * bands + 0.14 * threads + 0.12 * waves
      let color
      if (id === "earth") {
        // Procedural ocean/land and bright cloud cover (not a terrain map).
        const land = Math.sin(longitude * 3 + Math.cos(latitude * 5) * 2) +
          Math.cos(longitude * 7 - latitude * 7) * 0.48 > 0.68
        const cloud = Math.sin(latitude * 32 + warp * 2.2) * 0.5 +
          Math.cos(longitude * 17 - latitude * 23) * 0.3
        const base = land ? [58, 119, 94] : palette.base
        const t = clamp((cloud - 0.22) * 1.7) * 0.92
        color = [0, 1, 2].map(i => mix(base[i], palette.pale[i], t))
      } else {
        const banded = ["venus", "jupiter", "saturn", "uranus", "neptune"].includes(id)
        const amount = clamp((turbulence - (banded ? 0.23 : 0.38)) * (banded ? 1.8 : 1.2))
        const base = banded ? palette.base : palette.dark
        const bright = palette.pale
        color = [0, 1, 2].map(i => mix(base[i], bright[i], amount * pole + (1 - pole) * 0.4))
      }
      const index = (y * width + x) * 4
      for (let i = 0; i < 3; i++) pixels[index + i] = color[i]
      pixels[index + 3] = 255
    }
  }
  return {width, height, pixels}
}
