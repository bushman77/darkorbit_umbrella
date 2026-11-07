// Offline rendering smoke check for the desktop package.
// It intentionally does not open a socket, use tokens or mutate game state.
import {drawSolarAtlas} from "./game/solar_atlas.mjs"

const canvas = document.querySelector("#preview-cockpit")
const svg = document.querySelector("#preview-atlas")
const error = document.querySelector("#render-error")
const surface = document.querySelector(".render-surface")
let view = null
let frame = null
let mode = "atlas"

const own = {
  id: "preview-pilot", kind: "player",
  render: {x: 0, y: 0, z: 0}, angle: 0,
  orientation: {x: 0, y: 0, z: 0, w: 1},
  attitude: {yaw: 0, pitch: 0, roll: 0},
  angularVelocity: {yaw: 0, pitch: 0, roll: 0},
  velocity: {x: 0, y: 0, z: 0}, throttle: 0,
  hull: 100, maxHull: 100, shields: 100, maxShields: 100,
  attackRange: 600, flightMode: "conventional",
}
const fixture = {
  entities: new Map([[own.id, own]]),
  selfId: own.id,
  selectedTargetId: null,
  beams: [],
  navComputer: null,
  orbitalBase: null,
  lastLaserFeedback: null,
}

function resize() {
  if (!view || mode === "atlas") return
  const {width, height} = surface.getBoundingClientRect()
  view.resize(width, height, window.devicePixelRatio || 1)
}

function renderFrame(time) {
  if (mode === "atlas" || !view) return
  view.render(fixture, time)
  frame = requestAnimationFrame(renderFrame)
}

async function selectMode(next) {
  if (frame !== null) cancelAnimationFrame(frame)
  frame = null
  mode = next
  error.hidden = true
  for (const button of document.querySelectorAll("[data-render-mode]")) {
    button.setAttribute("aria-pressed", String(button.dataset.renderMode === next))
  }
  svg.hidden = next !== "atlas"
  canvas.hidden = next === "atlas"
  if (next === "atlas") {
    drawSolarAtlas(svg, {selectedId: "earth", focus: "system"})
    return
  }
  try {
    if (!view) {
      const {StereoSpaceView} = await import("./game/stereo_view.js")
      view = new StereoSpaceView(canvas)
    }
    view.setMode(next)
    resize()
    frame = requestAnimationFrame(renderFrame)
  } catch (cause) {
    error.textContent = "Local WebGL rendering failed: " + (cause?.message ?? String(cause))
    error.hidden = false
  }
}

for (const button of document.querySelectorAll("[data-render-mode]")) {
  button.addEventListener("click", () => selectMode(button.dataset.renderMode))
}
window.addEventListener("resize", resize)
selectMode("atlas")
