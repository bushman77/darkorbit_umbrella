import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import test from "node:test"

import {
  COCKPIT_LAYOUT_VERSION,
  CockpitWindowManager,
  clampWindowPosition,
  cockpitStorageKey,
  sanitizeCockpitLayout,
} from "./cockpit_window_manager.mjs"

class FakeClassList {
  constructor() {
    this.values = new Set()
  }

  add(...values) {
    for (const value of values) this.values.add(value)
  }

  remove(...values) {
    for (const value of values) this.values.delete(value)
  }

  toggle(value, force) {
    const enabled = force === undefined ? !this.values.has(value) : force
    if (enabled) this.values.add(value)
    else this.values.delete(value)
    return enabled
  }

  contains(value) {
    return this.values.has(value)
  }
}

class FakeEventTarget {
  constructor({tagName = "div", width = 320, height = 220, dataset = {}} = {}) {
    this.tagName = tagName
    this.width = width
    this.height = height
    this.offsetWidth = width
    this.offsetHeight = height
    this.dataset = {...dataset}
    this.style = {}
    this.hidden = false
    this.classList = new FakeClassList()
    this.attributes = new Map()
    this.listeners = new Map()
    this.queries = new Map()
    this.queryLists = new Map()
    this.capturedPointers = new Set()
    this.textContent = ""
  }

  addEventListener(type, listener) {
    const listeners = this.listeners.get(type) || []
    listeners.push(listener)
    this.listeners.set(type, listeners)
  }

  removeEventListener(type, listener) {
    const listeners = this.listeners.get(type) || []
    this.listeners.set(type, listeners.filter(candidate => candidate !== listener))
  }

  dispatch(type, properties = {}) {
    const event = {
      button: 0,
      buttons: 1,
      clientX: 0,
      clientY: 0,
      code: "",
      pointerId: 1,
      currentTarget: this,
      target: this,
      defaultPrevented: false,
      propagationStopped: false,
      preventDefault() {
        this.defaultPrevented = true
      },
      stopPropagation() {
        this.propagationStopped = true
      },
      ...properties,
    }
    for (const listener of this.listeners.get(type) || []) listener(event)
    return event
  }

  register(selector, element) {
    this.queries.set(selector, element)
    return element
  }

  registerAll(selector, elements) {
    this.queryLists.set(selector, elements)
  }

  querySelector(selector) {
    return this.queries.get(selector) || null
  }

  querySelectorAll(selector) {
    return this.queryLists.get(selector) || []
  }

  setAttribute(name, value) {
    this.attributes.set(name, String(value))
  }

  getAttribute(name) {
    return this.attributes.get(name)
  }

  getBoundingClientRect() {
    return {width: this.width, height: this.height}
  }

  closest(selector) {
    return selector === "button" && this.tagName === "button" ? this : null
  }

  setPointerCapture(pointerId) {
    this.capturedPointers.add(pointerId)
  }

  hasPointerCapture(pointerId) {
    return this.capturedPointers.has(pointerId)
  }

  releasePointerCapture(pointerId) {
    this.capturedPointers.delete(pointerId)
  }
}

class FakeStorage {
  constructor() {
    this.values = new Map()
    this.writes = 0
  }

  getItem(key) {
    return this.values.get(key) ?? null
  }

  setItem(key, value) {
    this.writes += 1
    this.values.set(key, value)
  }
}

const button = () => new FakeEventTarget({tagName: "button", width: 20, height: 20})

const setup = ({storage = new FakeStorage(), width = 1366, height = 768} = {}) => {
  const root = new FakeEventTarget()
  const windowTarget = new FakeEventTarget()
  windowTarget.innerWidth = width
  windowTarget.innerHeight = height
  const documentTarget = new FakeEventTarget()

  const dimensions = {
    ship_status: {width: 368, height: 340},
    target_info: {width: 336, height: 330},
    minimap: {width: 272, height: 210},
  }
  const windows = {}
  const handles = {}
  const collapseButtons = {}
  const hideButtons = {}

  for (const [id, size] of Object.entries(dimensions)) {
    const element = new FakeEventTarget({dataset: {cockpitWindow: id}, ...size})
    const handle = new FakeEventTarget({tagName: "header", width: size.width, height: 52})
    const collapse = button()
    const hide = button()
    element.register("[data-cockpit-drag-handle]", handle)
    element.register("[data-cockpit-collapse]", collapse)
    element.register("[data-cockpit-hide]", hide)
    windows[id] = element
    handles[id] = handle
    collapseButtons[id] = collapse
    hideButtons[id] = hide
  }
  root.registerAll("[data-cockpit-window]", Object.values(windows))

  const lock = button()
  const lockLabel = new FakeEventTarget()
  lock.register("[data-cockpit-lock-label]", lockLabel)
  const reset = button()
  const menu = new FakeEventTarget()
  menu.hidden = true
  const menuToggle = button()
  root.register("[data-cockpit-lock-toggle]", lock)
  root.register("[data-cockpit-reset]", reset)
  root.register("[data-cockpit-menu]", menu)
  root.register("[data-cockpit-menu-toggle]", menuToggle)

  const visibilityControls = Object.keys(windows).map(id => {
    const control = button()
    control.dataset.cockpitVisibility = id
    control.register("[data-cockpit-visibility-status]", new FakeEventTarget())
    return control
  })
  root.registerAll("[data-cockpit-visibility]", visibilityControls)

  const manager = new CockpitWindowManager({
    root,
    playerId: 42,
    storage,
    windowTarget,
    documentTarget,
  }).start()

  return {
    collapseButtons,
    documentTarget,
    handles,
    hideButtons,
    lock,
    manager,
    menu,
    menuToggle,
    reset,
    root,
    storage,
    visibilityControls,
    windows,
    windowTarget,
  }
}

test("dragging is restricted to an unlocked title bar and clamped to the viewport", () => {
  const context = setup()
  const handle = context.handles.ship_status
  const initial = {...context.manager.layout.windows.ship_status}

  handle.dispatch("pointerdown", {pointerId: 7, clientX: 100, clientY: 100})
  handle.dispatch("pointermove", {pointerId: 7, clientX: 500, clientY: 400})
  assert.deepEqual(context.manager.layout.windows.ship_status, initial)
  assert.equal(handle.hasPointerCapture(7), false)

  context.lock.dispatch("click")
  handle.dispatch("pointerdown", {pointerId: 7, clientX: 100, clientY: 100})
  assert.equal(handle.hasPointerCapture(7), true)
  handle.dispatch("pointermove", {pointerId: 7, clientX: 5_000, clientY: 5_000})
  handle.dispatch("pointerup", {pointerId: 7})

  assert.deepEqual(
    {x: context.manager.layout.windows.ship_status.x, y: context.manager.layout.windows.ship_status.y},
    {x: 986, y: 326}
  )
  assert.equal(handle.hasPointerCapture(7), false)
  assert.match(context.windows.ship_status.style.transform, /986px, 326px/)
})

test("collapse, expansion, hide, restore, and reset update accessible controls", () => {
  const context = setup()
  const window = context.windows.target_info
  const collapse = context.collapseButtons.target_info

  collapse.dispatch("click")
  assert.equal(context.manager.layout.windows.target_info.collapsed, true)
  assert.equal(window.classList.contains("is-collapsed"), true)
  assert.equal(collapse.getAttribute("aria-expanded"), "false")

  collapse.dispatch("click")
  assert.equal(context.manager.layout.windows.target_info.collapsed, false)
  assert.equal(collapse.getAttribute("aria-expanded"), "true")

  context.hideButtons.target_info.dispatch("click")
  assert.equal(window.hidden, true)
  const visibility = context.visibilityControls.find(control => control.dataset.cockpitVisibility === "target_info")
  visibility.dispatch("click")
  assert.equal(window.hidden, false)

  context.manager.setLocked(false)
  context.manager.layout.windows.target_info.x = 400
  context.manager.setVisible("minimap", false)
  context.reset.dispatch("click")
  assert.equal(context.manager.layout.locked, true)
  assert.equal(context.manager.layout.windows.minimap.visible, true)
  assert.notEqual(context.manager.layout.windows.target_info.x, 400)
})

test("versioned per-player layouts persist and restore without sensitive identifiers", () => {
  const storage = new FakeStorage()
  const first = setup({storage})
  first.manager.setLocked(false)
  first.manager.layout.windows.ship_status.x = 444
  first.manager.toggleCollapsed("ship_status")
  first.manager.setVisible("minimap", false)
  first.manager.persist()

  const restored = setup({storage})
  assert.equal(restored.manager.layout.locked, false)
  assert.equal(restored.manager.layout.windows.ship_status.x, 444)
  assert.equal(restored.manager.layout.windows.ship_status.collapsed, true)
  assert.equal(restored.manager.layout.windows.minimap.visible, false)
  assert.equal(cockpitStorageKey(42), "darkorbit:cockpit-layout:v1:player:42")
})

test("corrupted, incompatible, and unavailable storage fall back safely", () => {
  const malformed = new FakeStorage()
  malformed.values.set(cockpitStorageKey(42), "{not-json")
  const context = setup({storage: malformed})
  assert.equal(context.manager.layout.version, COCKPIT_LAYOUT_VERSION)
  assert.equal(context.manager.layout.locked, true)
  assert.equal(context.manager.layout.windows.minimap.visible, true)

  const defaults = context.manager.defaults
  assert.equal(sanitizeCockpitLayout({version: 999}, defaults), defaults)
  const invalidFields = sanitizeCockpitLayout(
    {
      version: COCKPIT_LAYOUT_VERSION,
      locked: "not-a-boolean",
      windows: {ship_status: {x: null, y: "100", visible: "yes", collapsed: 1}},
    },
    defaults
  )
  assert.deepEqual(invalidFields.windows.ship_status, defaults.windows.ship_status)
  assert.equal(invalidFields.locked, defaults.locked)

  const failingStorage = {
    getItem() {
      throw new Error("storage blocked")
    },
    setItem() {
      throw new Error("storage blocked")
    },
  }
  assert.doesNotThrow(() => setup({storage: failingStorage}).manager.setLocked(false))
})

test("viewport resize clamps floating windows and enables the narrow dock", () => {
  const context = setup({width: 1920, height: 1080})
  context.manager.layout.windows.ship_status.x = 1_700
  context.manager.layout.windows.ship_status.y = 900
  context.windowTarget.innerWidth = 800
  context.windowTarget.innerHeight = 700
  context.windowTarget.dispatch("resize")
  assert.deepEqual(
    {x: context.manager.layout.windows.ship_status.x, y: context.manager.layout.windows.ship_status.y},
    {x: 420, y: 258}
  )

  context.windowTarget.innerWidth = 600
  context.windowTarget.dispatch("resize")
  assert.equal(context.root.classList.contains("is-compact"), true)
  assert.equal(context.root.dataset.cockpitMode, "docked")

  context.windowTarget.innerWidth = 1_366
  context.windowTarget.innerHeight = 600
  context.windowTarget.dispatch("resize")
  assert.equal(context.root.classList.contains("is-compact"), true)
})

test("pointer cleanup releases capture on cancel, blur, visibility, and destroy", async t => {
  const cases = [
    ["cancel", context => context.handles.ship_status.dispatch("pointercancel", {pointerId: 3})],
    ["blur", context => context.windowTarget.dispatch("blur")],
    ["visibility", context => {
      context.documentTarget.hidden = true
      context.documentTarget.dispatch("visibilitychange")
    }],
    ["destroy", context => context.manager.destroy()],
  ]

  for (const [name, cleanup] of cases) {
    await t.test(name, () => {
      const context = setup()
      context.manager.setLocked(false)
      const handle = context.handles.ship_status
      handle.dispatch("pointerdown", {pointerId: 3, clientX: 50, clientY: 50})
      assert.equal(handle.hasPointerCapture(3), true)
      cleanup(context)
      assert.equal(handle.hasPointerCapture(3), false)
      assert.equal(context.manager.drag, null)
    })
  }
})

test("cockpit pointer boundaries do not leak navigation events to the canvas layer", () => {
  const context = setup()
  const event = context.windows.minimap.dispatch("pointerdown", {pointerId: 11})
  assert.equal(event.propagationStopped, true)
})

test("keyboard movement is accessible while hotbar and combat keys remain untouched", () => {
  const context = setup()
  context.manager.setLocked(false)
  const handle = context.handles.ship_status
  const before = context.manager.layout.windows.ship_status.x

  const digit = handle.dispatch("keydown", {code: "Digit1"})
  const space = handle.dispatch("keydown", {code: "Space"})
  assert.equal(digit.defaultPrevented, false)
  assert.equal(space.defaultPrevented, false)

  const arrow = handle.dispatch("keydown", {code: "ArrowRight", shiftKey: true})
  assert.equal(arrow.defaultPrevented, true)
  assert.equal(context.manager.layout.windows.ship_status.x, before + 10)
})

test("position clamping preserves safe top and hotbar boundaries", () => {
  assert.deepEqual(
    clampWindowPosition({x: -500, y: 5_000}, {width: 300, height: 200}, {width: 1_000, height: 700}),
    {x: 12, y: 398}
  )
})

test("cockpit motion honors the application reduced-motion preference", async () => {
  const css = await readFile(new URL("../../css/app.css", import.meta.url), "utf8")
  assert.match(css, /@media \(prefers-reduced-motion: reduce\)/)
  assert.match(css, /transition-duration: 0\.01ms !important/)
})
