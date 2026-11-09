import {greenStarbaseInteriorVisible} from "./green_starbase_interior_state.mjs"
import {buildGreenStarbaseArt} from "./green_starbase_art.mjs"

// Shared lightweight Three.js station interior. The docked ship has no actor
// here: the pilot's authenticated room pose is replicated by MapServer, and
// both the desktop and paired SBS viewer render the same local geometry.
export class GreenStarbaseInterior {
  constructor(THREE, scene, {lowPower} = {}) {
    this.scene = scene
    this.lowPower = typeof lowPower === "boolean" ? lowPower :
      typeof navigator !== "undefined" &&
      /Android|iPhone|iPad/i.test(navigator.userAgent || "")
    this.THREE = THREE
    this.materials = []
    this.geometries = []
    this.textures = []
    this.lights = []
    this.doorOpen = 0
    this.lastUpdatedAt = null
    this.attendantsLoaded = false
    this.build()
  }

  build() {
    const T = this.THREE
    const group = new T.Group()
    group.name = "Space Nova / Green Starbase / Hangar and concourse"
    group.userData.nonInteractive = true
    this.node = group
    this.scene.add(group)

    const material = (color, emissive = null) => {
      const m = emissive === null
        ? new T.MeshStandardMaterial({color, roughness: 0.82, metalness: 0.22,
          flatShading: true})
        : new T.MeshBasicMaterial({color: emissive})
      this.materials.push(m)
      return m
    }

    const steel = material(0x293940)
    const decking = material(0x23343b)
    const bulkhead = material(0x172831)
    const supports = material(0x45535b)
    const rail = material(0x506e67)
    const light = material(0x74eec4, 0x74eec4)
    const amber = material(0xffc46b, 0xffc46b)
    const glass = material(0x184d55, 0x184d55)
    const commerce = material(0x2e6770)
    const maintenance = material(0x465d57)
    const equipment = material(0x576d51)
    const administration = material(0x36485c)

    const add = (geometry, surface, x, y, z, rotation = null) => {
      this.geometries.push(geometry)
      const mesh = new T.Mesh(geometry, surface)
      mesh.position.set(x, y, z)
      if (rotation) mesh.rotation.set(...rotation)
      group.add(mesh)
      return mesh
    }
    const box = (dimensions, surface, position) =>
      add(new T.BoxGeometry(...dimensions), surface, ...position)
    const floor = (width, depth, x, z) => {
      box([width, 1.5, depth], decking, [x, -5.5, z])
      box([width, 2.0, depth], steel, [x, 33, z])
    }
    const wallX = (z, left, right, surface = bulkhead, y = 13) =>
      box([right - left, 39, 2], surface, [(right + left) / 2, y, z])
    const wallZ = (x, z1, z2, surface = bulkhead) =>
      box([2, 39, Math.abs(z2 - z1)], surface,
        [x, 13, (z1 + z2) / 2])

    // Optional local in-world signage: generated on each device, never
    // streamed as textures. Node tests can construct the bare geometry.
    const sign = (text, x, y, z, width = 15) => {
      if (typeof document === "undefined" || !T.CanvasTexture ||
          !T.PlaneGeometry) return
      const canvas = document.createElement("canvas")
      canvas.width = 768
      canvas.height = 160
      const context = canvas.getContext("2d")
      if (!context) return
      context.fillStyle = "#05231d"
      context.fillRect(0, 0, canvas.width, canvas.height)
      context.strokeStyle = "#4fecad"
      context.lineWidth = 8
      context.strokeRect(6, 6, 756, 148)
      context.fillStyle = "#b5ffe4"
      context.font = "bold 58px monospace"
      context.textAlign = "center"
      context.fillText(text, 384, 103, 724)
      const texture = new T.CanvasTexture(canvas)
      texture.colorSpace = T.SRGBColorSpace
      this.textures.push(texture)
      const surface = new T.MeshBasicMaterial({
        map: texture, side: T.DoubleSide, depthWrite: true,
      })
      this.materials.push(surface)
      add(new T.PlaneGeometry(width, width * 160 / 768),
        surface, x, y, z)
    }

    this.addSign = sign

    // The original open arrival hangar is retained. The former opaque rear
    // wall is now split around a real, traversable services airlock.
    floor(84, 156, 0, -8)
    wallZ(-42, -86, 70)
    wallZ(42, -86, 70)
    wallX(-85, -42, -9, steel)
    wallX(-85, 9, 42, steel)
    box([18, 16, 3], steel, [0, 25, -85])

    box([45, 0.3, 60], steel, [0, -4.15, -19])
    for (const x of [-23, 23]) {
      box([1.1, 0.24, 62], light, [x, -3.90, -19])
      box([2.2, 7, 8], supports, [x, -0.6, -43])
      box([1.4, 1, 7], amber, [x * 0.91, 2.6, -43])
    }
    for (const z of [-48, -15, 13]) {
      box([43, 0.22, 1], light, [0, -3.91, z])
    }
    for (const z of [-74, -38, -2, 34, 62]) {
      for (const x of [-39, 39]) {
        box([3, 34, 4], supports, [x, 12, z])
        box([0.8, 23, 0.4], light, [x * 0.94, 13, z - 2.2])
      }
      box([80, 2, 3], supports, [0, 29, z])
      for (const x of [-21, 0, 21]) {
        box([12, 0.25, 1.1], light, [x, 27.9, z])
      }
    }
    for (const side of [-1, 1]) {
      box([11, 1.8, 136], decking, [side * 35, -2.6, -7])
      box([0.8, 2.8, 136], rail, [side * 28, -0.4, -7])
      for (const z of [-62, -37, 6, 28]) {
        box([7, 5, 6], supports, [side * 34, 0.6, z])
        box([5.8, 3.5, 0.24], glass, [side * 34, 1.0, z + 3.1])
        box([5.8, 0.25, 0.5], amber, [side * 34, 3.2, z + 3.4])
      }
    }

    // Sliding main door: left and right leafs retract away from the passage.
    // Opening is visual only; the authoritative collision layout determines
    // whether the player may pass through the eight-unit-wide threshold.
    for (const x of [-9, 9]) box([1.1, 23, 1.1], light, [x, 6.4, -83.2])
    box([20, 1.2, 1.2], light, [0, 18.2, -83.2])
    sign("STATION ACCESS", 0, 23.3, -82.1, 17)
    this.doorLeft = box([7.9, 20, 0.7], glass, [-3.95, 5.5, -83.1])
    this.doorRight = box([7.9, 20, 0.7], glass, [3.95, 5.5, -83.1])
    box([0.32, 19, 0.78], light, [-7.85, 5.5, -83.0])
    box([0.32, 19, 0.78], light, [7.85, 5.5, -83.0])

    // Short, physically connected airlock from the hangar to the concourse.
    // Hangar floor ends at z=-86 and concourse starts at -103.
    // Fill the gap, rather than overlapping both slab surfaces (z-fighting).
    floor(18, 17, 0, -94.5)
    wallZ(-9, -106.5, -82)
    wallZ(9, -106.5, -82)
    for (const z of [-99, -92, -86]) {
      box([0.4, 0.2, 3.2], light, [-6.5, -4.5, z])
      box([0.4, 0.2, 3.2], light, [6.5, -4.5, z])
      box([11, 0.3, 1], light, [0, 29, z])
    }

    // Central concourse. Three doorways on each side/end lead to the six
    // future service desks. All apertures correspond to MapServer collision.
    floor(70, 84, 0, -145)
    wallX(-105, -35, -8)
    wallX(-105, 8, 35)
    box([16, 16, 2], supports, [0, 25, -105])
    sign("CONCOURSE", 0, 22, -104, 14)

    for (const side of [-1, 1]) {
      const x = side * 34
      wallZ(x, -125, -103)
      wallZ(x, -165, -134)
      wallZ(x, -186, -175)
      for (const z of [-129, -170]) {
        box([1.2, 22, 1.2], light, [x, 7, z - 5.1])
        box([1.2, 22, 1.2], light, [x, 7, z + 5.1])
        box([2.5, 1, 11], supports, [x, 17.5, z])
      }
    }

    // The far wall contains two independent office doors.
    wallX(-186.5, -35, -21)
    wallX(-186.5, -11, 11)
    wallX(-186.5, 21, 35)
    // Slim door-edge strips sit entirely in front of the wall's concourse
    // face (wall center z=-186.5, thickness 2 => near face z=-185.5).
    // The old strips ended on exactly that face, causing depth flicker.
    for (const x of [-16, 16]) {
      box([0.45, 21, 0.35], light, [x - 5.1, 7, -185.15])
      box([0.45, 21, 0.35], light, [x + 5.1, 7, -185.15])
      box([11, 1.1, 1], supports, [x, 17.5, -186])
    }
    for (const z of [-116, -140, -164, -181]) {
      for (const x of [-20, 0, 20]) {
        box([9, 0.3, 1], light, [x, 30.8, z])
      }
    }
    // Directory kiosk. Not an invented trade terminal: future transactions
    // will be server-authorized and attached to actual room interactions.
    box([8, 4, 4], supports, [0, -2.1, -120])
    box([7, 3, 0.35], glass, [0, 1.4, -117.8])
    sign("SERVICE DIRECTORY", 0, 4.7, -117.4, 13)

    // Both service wings have two rooms. Open portals lie at z=-129 and -170.
    // The walls not occupied by a doorway remain solid.
    const wings = [
      {side: -1, z: -130, title: "REPAIRS", surface: maintenance},
      {side: 1, z: -130, title: "TRADE EXCHANGE", surface: commerce},
      {side: -1, z: -168, title: "OUTFITTING", surface: equipment},
      {side: 1, z: -168, title: "RESUPPLY", surface: maintenance},
    ]
    for (const {side, z, title, surface} of wings) {
      // Meet the concourse slab at x=+/-35 without a 1-unit overlap.
      const x = side * 49
      const front = z + 17
      const back = z - 17
      const gateZ = z === -130 ? -129 : -170
      floor(28, 34, x, z)
      wallX(front, x - 14, x + 14, surface)
      wallX(back, x - 14, x + 14, surface)
      wallZ(side * 63, back, front, surface)
      // Concourse owns the inner wall around both doors. Another pair
      // here at x=+/-34 would be exactly coplanar and flicker.
      box([11, 0.24, 7], light, [side * 36.5, -4.55, gateZ])
      // The label is readable from the corridor and remains stereoscopic.
      sign(title, side * 30.5, 20, gateZ, 12.5)
      box([16, 2.2, 5], supports, [x, -3.4, z - 9])
      box([11, 3.4, 0.35], glass, [x, 0.2, z - 6.3])
      for (const lamp of [-9, 9]) {
        box([5.5, 0.3, 1], light, [x + lamp, 30.7, z])
      }
    }

    // Rear offices: actual separate navigable rooms, not clickable fake
    // buttons. NPC conversations and missions can be added afterward.
    for (const {x, title, surface} of [
      {x: -16, title: "MISSION OFFICE", surface: administration},
      {x: 16, title: "COMMUNICATIONS", surface: commerce},
    ]) {
      floor(24, 27, x, -200.5)
      const sideX = x < 0 ? [-28, -4] : [4, 28]
      wallZ(sideX[0], -214, -187, surface)
      wallZ(sideX[1], -214, -187, surface)
      wallX(-214, ...sideX, surface)
      // The concourse already owns the office doorway wall at z=-186.5.
      // An almost-coincident wall here shimmered in perspective.
      sign(title, x, 19.8, -190, 16)
      box([14, 2.5, 5], supports, [x, -3.4, -208])
      box([11, 3, 0.25], glass, [x, 0.1, -205.3])
      box([12, 0.3, 1], light, [x, 30.5, -201])
    }

    this.art = buildGreenStarbaseArt({
      THREE: T, box, add, sign,
      materials: this.materials, textures: this.textures,
      lowPower: this.lowPower,
    })

    const ambient = new T.HemisphereLight(0xc7e6dd, 0x101820, 1.65)
    this.scene.add(ambient)
    this.lights.push(ambient)
    const overhead = new T.DirectionalLight(0xe2f5eb, 2.2)
    overhead.position.set(-12, 28, 17)
    this.scene.add(overhead)
    this.lights.push(overhead)
  }

  // All characters are lightweight local models. MapServer controls their
  // identity and location; the HMD has no dialogue or service authority.
  buildAttendants(attendants) {
    if (this.attendantsLoaded || !Array.isArray(attendants) ||
        attendants.length === 0) return
    this.attendantsLoaded = true
    const T = this.THREE
    for (const npc of attendants) {
      if (!npc || !Number.isFinite(npc.x) || !Number.isFinite(npc.z) ||
          !Number.isInteger(npc.color) || typeof npc.name !== "string" ||
          typeof npc.role !== "string" || typeof npc.id !== "string") continue
      const uniform = new T.MeshStandardMaterial({
        color: npc.color, roughness: 0.8, metalness: 0.12,
      })
      const skin = new T.MeshStandardMaterial({
        color: npc.id === "comms" || npc.id === "trade" ? 0xa97857 : 0xd3a17f,
        roughness: 0.95, metalness: 0.0,
      })
      const hair = new T.MeshStandardMaterial({
        color: npc.id === "outfitting" || npc.id === "missions" ?
          0x6b4e36 : 0x263038, roughness: 0.9, metalness: 0.0,
      })
      const visor = new T.MeshBasicMaterial({color: 0x8de8cf})
      const shadow = new T.MeshStandardMaterial({
        color: 0x192930, roughness: 0.8,
      })
      this.materials.push(uniform, skin, hair, visor, shadow)
      const primitive = (kind, dims) => {
        if (kind === "head" && T.SphereGeometry) {
          return new T.SphereGeometry(dims[0], 12, 10)
        }
        if (kind === "tube" && T.CylinderGeometry) {
          return new T.CylinderGeometry(dims[0], dims[1], dims[2], 10)
        }
        return new T.BoxGeometry(...dims.slice(0, 3))
      }
      const part = (kind, dimensions, surface, dx, y, dz, label) => {
        const geometry = primitive(kind, dimensions)
        const mesh = new T.Mesh(geometry, surface)
        mesh.position.set(npc.x + dx, y, npc.z + dz)
        mesh.name = "attendant:" + npc.id + ":" + label
        this.geometries.push(geometry)
        this.node.add(mesh)
      }
      // Round, tapered bodies instead of eight rectangular block pieces.
      // The feet rest on the shared local floor (-4.75).
      part("tube", [0.43, 0.40, 2.85], shadow, -0.60, -3.25, 0, "left-leg")
      part("tube", [0.43, 0.40, 2.85], shadow, 0.60, -3.25, 0, "right-leg")
      part("tube", [1.30, 0.83, 4.35], uniform, 0, 0.25, 0, "torso")
      part("tube", [0.37, 0.33, 3.1], uniform, -1.37, 0.12, 0, "left-arm")
      part("tube", [0.37, 0.33, 3.1], uniform, 1.37, 0.12, 0, "right-arm")
      part("head", [0.95, 1.8, 1.8], skin, 0, 3.35, 0.03, "head")
      part("head", [0.98, 1.8, 1.8], hair, 0, 3.95, -0.29, "hair")
      part("box", [1.1, 0.22, 0.12], visor, 0, 0.82, 1.01, "badge")
      // Extra uniform trim is visual-only, separate from the eight-part
      // character identity set used by the shared SBS geometry tests.
      const detail = (dims, surface, dx, y, dz, name) => {
        const g = new T.BoxGeometry(...dims)
        const m = new T.Mesh(g, surface)
        m.position.set(npc.x + dx, y, npc.z + dz)
        m.name = "uniform:" + npc.id + ":" + name
        this.geometries.push(g)
        this.node.add(m)
      }
      detail([2.0, 0.25, 1.56], shadow, 0, -1.75, 0, "belt")
      detail([0.36, 0.3, 0.18], visor, -0.57, 1.32, 0.95, "insignia")
      detail([0.24, 0.12, 0.30], shadow, -1.39, -1.32, 0.30, "left-cuff")
      detail([0.24, 0.12, 0.30], shadow, 1.39, -1.32, 0.30, "right-cuff")
      this.addSign?.(npc.name, npc.x, 10.1, npc.z + 1.2, 15)
      this.addSign?.(npc.role.toUpperCase(), npc.x, 7.6, npc.z + 1.2, 14)
    }
  }

  // Door movement and NPCs remain presentation-only, never authoritative.
  update(pose, time, attendants = []) {
    this.buildAttendants(attendants)
    const near = pose && Number.isFinite(pose.x) &&
      Number.isFinite(pose.z) && Math.abs(pose.x) <= 14 &&
      pose.z < -69 && pose.z > -111
    const delta = this.lastUpdatedAt == null ? 0 :
      Math.min(0.1, Math.max(0, (time - this.lastUpdatedAt) / 1000))
    this.lastUpdatedAt = time
    this.doorOpen += (Number(Boolean(near)) - this.doorOpen) *
      Math.min(1, delta * 12)
    this.doorLeft.position.set(-3.95 - this.doorOpen * 8, 5.5, -83.1)
    this.doorRight.position.set(3.95 + this.doorOpen * 8, 5.5, -83.1)
  }

  dispose() {
    this.scene.remove(this.node)
    this.lights.forEach(light => this.scene.remove(light))
    this.geometries.forEach(geometry => geometry.dispose())
    this.materials.forEach(material => material.dispose())
    this.textures.forEach(texture => texture.dispose())
    this.geometries = []
    this.materials = []
    this.textures = []
    this.lights = []
  }
}

export {greenStarbaseInteriorVisible}
