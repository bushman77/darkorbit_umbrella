// Green Starbase's mid-poly art layer. Purely local Three.js presentation:
// the server remains authoritative for the walkable topology and all NPCs.
// Keep visual clutter out of open walkways until corresponding collision exists.
export const STARBASE_ART_VERSION = "modular-industrial-v1"

export function buildGreenStarbaseArt({
  THREE: T, box, add, sign, materials, textures, lowPower = false,
}) {
  const surface = (color, metalness = 0.46, roughness = 0.54) => {
    const result = new T.MeshStandardMaterial({color, metalness, roughness})
    materials.push(result)
    return result
  }
  const plate = surface(0x384953, 0.61, 0.42)
  const lowerPlate = surface(0x26363d)
  const inset = surface(0x101e25, 0.48, 0.7)
  const gunmetal = surface(0x48575e, 0.62, 0.35)
  const edge = surface(0x78928b, 0.48, 0.45)
  const green = new T.MeshBasicMaterial({color: 0x59f4bb})
  const cyan = new T.MeshBasicMaterial({color: 0x5ccbd6})
  const amber = new T.MeshBasicMaterial({color: 0xe3b54f})
  materials.push(green, cyan, amber)

  // One small reusable texture pattern with a dark steel panel, beveled
  // highlights, seams, maintenance scratches and inset fasteners.
  // CanvasTexture is created on the rendering device (including Android).
  const plateCanvas = () => {
    if (typeof document === "undefined" || !T.CanvasTexture) return null
    const canvas = document.createElement("canvas")
    canvas.width = 256
    canvas.height = 256
    const ctx = canvas.getContext("2d")
    if (!ctx) return null
    ctx.fillStyle = "#293b43"
    ctx.fillRect(0, 0, 256, 256)
    ctx.fillStyle = "#374b55"
    ctx.fillRect(12, 12, 232, 232)
    ctx.fillStyle = "#1a2d34"
    ctx.fillRect(19, 19, 218, 218)
    ctx.fillStyle = "#31434a"
    ctx.fillRect(23, 23, 210, 210)
    ctx.strokeStyle = "#63747a"
    ctx.lineWidth = 3
    ctx.strokeRect(15, 15, 226, 226)
    ctx.strokeStyle = "#17272e"
    ctx.lineWidth = 5
    ctx.strokeRect(7, 7, 242, 242)
    ctx.fillStyle = "#78888b"
    for (const x of [22, 234]) {
      for (const y of [22, 234]) {
        ctx.beginPath()
        ctx.arc(x, y, 3.5, 0, Math.PI * 2)
        ctx.fill()
      }
    }
    ctx.strokeStyle = "rgba(151,174,172,0.18)"
    ctx.lineWidth = 2
    for (let n = 0; n < 5; n++) {
      const v = 37 + n * 38
      ctx.beginPath()
      ctx.moveTo(v, 67)
      ctx.lineTo(v + 13, 67)
      ctx.stroke()
    }
    return canvas
  }

  const canvas = plateCanvas()
  const repeatMaterials = new Map()
  const surfaceFor = (w, d) => {
    if (!canvas) return plate
    const repeatX = Math.max(1, Math.round(w / 6))
    const repeatY = Math.max(1, Math.round(d / 6))
    const key = repeatX + "x" + repeatY
    if (repeatMaterials.has(key)) return repeatMaterials.get(key)
    const texture = new T.CanvasTexture(canvas)
    texture.colorSpace = T.SRGBColorSpace
    texture.wrapS = T.RepeatWrapping
    texture.wrapT = T.RepeatWrapping
    texture.repeat.set(repeatX, repeatY)
    texture.anisotropy = 4
    textures.push(texture)
    const material = new T.MeshStandardMaterial({
      map: texture, color: 0xffffff, metalness: 0.58, roughness: 0.53,
    })
    materials.push(material)
    repeatMaterials.set(key, material)
    return material
  }

  // Decorative floor skins float above the old structural slabs without
  // altering the MapServer walkable envelope. Adjacent rooms meet at edges.
  const floors = [
    [84, 156, 0, -8], [18, 17, 0, -94.5], [70, 84, 0, -145],
    [28, 34, -49, -130], [28, 34, 49, -130],
    [28, 34, -49, -168], [28, 34, 49, -168],
    [24, 27, -16, -200.5], [24, 27, 16, -200.5],
  ]
  for (const [w, d, x, z] of floors) {
    box([w - 0.16, 0.055, d - 0.16], surfaceFor(w, d), [x, -4.675, z])
    // Narrow floor skirt trim down either side of each room, not across
    // the threshold. No decorative geometry is considered solid.
    if (w < 80 && !lowPower) {
      box([0.24, 0.045, d - 1], inset, [x - w / 2 + 0.46, -4.61, z])
      box([0.24, 0.045, d - 1], inset, [x + w / 2 - 0.46, -4.61, z])
    }
  }

  // Wall panels: retain the existing structural walls and their door gaps.
  // Additional surfaces are offset by at least 0.13 units to prevent the
  // coplanar Z-fighting seen in the original concourse screenshots.
  const panelX = (z, lo, hi, facing = 1) => {
    if (hi <= lo + 0.8) return
    const length = hi - lo
    const front = z + facing * 1.22
    const center = (lo + hi) / 2
    const count = Math.max(1, Math.ceil(length / (lowPower ? 36 : 22)))
    const step = length / count
    for (let i = 0; i < count; i++) {
      const x = lo + (i + 0.5) * step
      box([step - 0.48, 25.0, 0.16], plate, [x, 10.3, front])
      box([step - 0.65, 0.32, 0.22], edge, [x, 22.8, front + facing * 0.14])
    }
    box([length - 0.9, 1.05, 0.24], lowerPlate,
      [center, -1.6, front + facing * 0.14])
    if (length > 15) {
      box([Math.min(7.5, length - 3), 2.2, 0.2], inset,
        [center, 1.8, front + facing * 0.19])
    }
  }
  const panelZ = (x, lo, hi, facing) => {
    if (hi <= lo + 0.8) return
    const n = Math.max(1, Math.ceil((hi - lo) / (lowPower ? 36 : 22)))
    const step = (hi - lo) / n
    for (let i = 0; i < n; i++) {
      const z = lo + (i + 0.5) * step
      const front = x + facing * 1.22
      box([0.16, 25.0, step - 0.48], plate, [front, 10.3, z])
      box([0.24, 0.34, step - 0.7], edge,
        [front + facing * 0.15, 22.8, z])
    }
    box([0.24, 1.05, hi - lo - 0.85], lowerPlate,
      [x + facing * 1.38, -1.6, (hi + lo) / 2])
  }
  for (const side of [-1, 1]) {
    const inside = -side
    panelZ(side * 34, -125, -103, inside)
    panelZ(side * 34, -165, -134, inside)
    panelZ(side * 34, -186, -175, inside)
    if (!lowPower) {
      panelZ(side * 63, -147, -113, inside)
      panelZ(side * 63, -185, -151, inside)
      panelZ(side * 42, -86, 70, inside)
    }
    panelZ(side * 9, -106.5, -82, inside)
  }
  panelX(-186.5, -35, -21)
  panelX(-186.5, -11, 11)
  panelX(-186.5, 21, 35)
  panelX(-105, -35, -8, -1)
  panelX(-105, 8, 35, -1)
  for (const side of [-1, 1]) {
    const x = side * 49
    for (const z of [-130, -168]) {
      panelX(z + 17, x - 14, x + 14, -1)
      panelX(z - 17, x - 14, x + 14, 1)
    }
  }

  // Exposed ceiling services and recessed strip-light frames. Directional
  // shadows are deliberately not used for mobile SBS GPU economy.
  for (const z of [-114, -137, -160, -181]) {
    if (lowPower && z !== -137 && z !== -181) continue
    box([67, 1.0, 1.7], gunmetal, [0, 29.4, z])
    for (const x of [-21, 0, 21]) {
      box([10.2, 0.17, 1.0], inset, [x, 28.75, z])
      box([8.5, 0.12, 0.72], cyan, [x, 28.59, z])
    }
  }
  if (T.CylinderGeometry) {
    const pipe = (x, y, z, len, radius, mat, rot) => {
      add(new T.CylinderGeometry(radius, radius, len, 8),
        mat, x, y, z, rot)
    }
    for (const x of [-29, 29]) {
      pipe(x, 29.5, -144.5, 78, 0.62, gunmetal, [Math.PI / 2, 0, 0])
      pipe(x + (x < 0 ? 1.3 : -1.3), 30.2, -144.5, 78, 0.18, green,
        [Math.PI / 2, 0, 0])
    }
  }

  // The remote concourse wall is also the Green Starbase wayfinding focus.
  // It sits between the two rear offices, leaving both entrances unchanged.
  box([18.6, 27, 0.18], inset, [0, 11.4, -185.02])
  box([19, 0.55, 0.22], gunmetal, [0, 24.8, -184.87])
  box([19, 0.55, 0.22], gunmetal, [0, -2.1, -184.87])
  for (const angle of [Math.PI / 4, -Math.PI / 4]) {
    add(new T.BoxGeometry(6.5, 0.55, 0.20), green, 0, 16.6, -184.62,
      [0, 0, angle])
  }
  sign("SPACE NOVA", 0, 11.5, -184.59, 16)
  sign("GREEN STARBASE", 0, 6.8, -184.58, 16)
  for (const x of [-6.6, -3.3, 0, 3.3, 6.6]) {
    box([1.6, 0.48, 0.23], green, [x, -1.4, -184.56])
  }

  // Floating service-room banners obstructed kiosks and attendants.
  // Keep room labels in the station directory and HUD instead.

  // Industrial kiosks, screen terminals, rear-rack supplies and cargo
  // storage remain behind the existing counters (not in the passage).
  const shelves = (x, z) => {
    if (lowPower) {
      box([5.9, 0.3, 2.3], edge, [x, -3, z])
      box([5.9, 0.3, 2.3], edge, [x, 1.0, z])
      box([2.2, 1.5, 1.4], plate, [x, 2.0, z])
      return
    }
    for (const dx of [-2.5, 2.5]) {
      box([0.35, 9.0, 0.5], gunmetal, [x + dx, -0.5, z])
    }
    for (const y of [-3.0, 0.0, 3.0]) {
      box([5.9, 0.30, 2.3], edge, [x, y, z])
    }
    for (const dx of [-1.4, 1.25]) {
      box([2.0, 1.5, 1.4], plate, [x + dx, 1.0, z])
    }
    box([2.3, 0.18, 0.12], amber, [x, 1.65, z + 0.80])
  }
  const kiosk = (x, z) => {
    box([15.6, 0.22, 0.25], gunmetal, [x, -1.9, z + 3.7])
    for (const dx of [-7.2, 7.2]) {
      box([0.65, 3.9, 0.7], gunmetal, [x + dx, -2.9, z + 3.7])
      box([0.28, 1.8, 0.18], green, [x + dx, -2.4, z + 4.13])
    }
    box([9.6, 0.16, 0.6], cyan, [x, -2.7, z + 4.08])
    box([5.9, 2.9, 0.3], inset, [x, 2.0, z + 5.2])
    box([5.2, 2.2, 0.10], cyan, [x, 2.0, z + 5.39])
    // Work surface and nearby visitor sightline stay clear of signs.
    // Narrow rear offices use closer racks so they do not poke through walls.
    const rackOffset = Math.abs(x) === 16 ? 7.7 : 9.3
    if (!lowPower) shelves(x - rackOffset, z - 0.6)
    shelves(x + rackOffset, z - 0.6)
  }
  for (const [x, z] of [
    [-49, -141], [49, -141],
    [-49, -179], [49, -179],
    [-16, -209], [16, -209],
  ]) kiosk(x, z)

  // Hazard marks and vent strips are baked into floor-surface geometry,
  // without installing invisible walls or changing walk collision.
  if (!lowPower) {
    for (const z of [-114, -139, -164, -181]) {
      for (const x of [-29, 29]) {
        box([1.15, 0.055, 6.5], inset, [x, -4.57, z])
        box([0.94, 0.06, 3.7], gunmetal, [x, -4.52, z])
      }
    }
    for (const z of [-124, -144, -164, -179]) {
      for (const x of [-26, 26]) {
        box([2.5, 0.065, 0.48], amber, [x, -4.56, z])
      }
    }
  }

  return {version: STARBASE_ART_VERSION, floorAreas: floors.length,
    quality: lowPower ? "mobile" : "desktop"}
}
