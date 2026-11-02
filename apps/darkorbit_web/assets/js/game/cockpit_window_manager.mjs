export const COCKPIT_LAYOUT_VERSION = 1
export const COCKPIT_STORAGE_PREFIX = "darkorbit:cockpit-layout:v1"
export const COCKPIT_COMPACT_BREAKPOINT = 720
export const MINIMAP_DEFAULT_WIDTH = 272
export const MINIMAP_MIN_WIDTH = 192
export const MINIMAP_MAX_WIDTH = 520
export const MINIMAP_WIDTH_STEP = 40

const MINIMAP_VIEWPORT_INSET = 24

export const DEFAULT_COCKPIT_WINDOWS = Object.freeze({
  ship_status: Object.freeze({
    anchor: "top-left",
    offsetX: 24,
    offsetY: 96,
    visible: true,
    collapsed: false,
  }),
  minimap: Object.freeze({
    anchor: "bottom-right",
    offsetX: 24,
    offsetY: 126,
    visible: true,
    collapsed: false,
    width: MINIMAP_DEFAULT_WIDTH,
  }),
})

const finite = value => typeof value === "number" && Number.isFinite(value)
const boolean = value => typeof value === "boolean"

export const clampMinimapWidth = (width, viewportWidth = Number.POSITIVE_INFINITY) => {
  const requested = finite(width) ? width : MINIMAP_DEFAULT_WIDTH
  const available = finite(viewportWidth)
    ? Math.max(MINIMAP_MIN_WIDTH, viewportWidth - MINIMAP_VIEWPORT_INSET)
    : MINIMAP_MAX_WIDTH

  return Math.min(Math.max(requested, MINIMAP_MIN_WIDTH), MINIMAP_MAX_WIDTH, available)
}

export const cockpitStorageKey = playerId =>
  `${COCKPIT_STORAGE_PREFIX}:player:${String(playerId || "guest")}`

export const clampWindowPosition = (
  position,
  size,
  viewport,
  safeArea = {top: 80, right: 12, bottom: 102, left: 12}
) => {
  const maximumX = Math.max(safeArea.left, viewport.width - size.width - safeArea.right)
  const maximumY = Math.max(safeArea.top, viewport.height - size.height - safeArea.bottom)

  return {
    x: Math.min(Math.max(Number(position.x) || 0, safeArea.left), maximumX),
    y: Math.min(Math.max(Number(position.y) || 0, safeArea.top), maximumY),
  }
}

export const defaultWindowPosition = (definition, size, viewport) => {
  const right = viewport.width - size.width - definition.offsetX
  const bottom = viewport.height - size.height - definition.offsetY

  return {
    x: definition.anchor.endsWith("right") ? right : definition.offsetX,
    y: definition.anchor.startsWith("bottom") ? bottom : definition.offsetY,
  }
}

export const sanitizeCockpitLayout = (saved, defaults) => {
  if (!saved || saved.version !== COCKPIT_LAYOUT_VERSION || !saved.windows) return defaults

  const windows = {}
  for (const [id, fallback] of Object.entries(defaults.windows)) {
    const candidate = saved.windows[id]
    const window = {
      x: finite(candidate?.x) ? candidate.x : fallback.x,
      y: finite(candidate?.y) ? candidate.y : fallback.y,
      visible: boolean(candidate?.visible) ? candidate.visible : fallback.visible,
      collapsed: boolean(candidate?.collapsed) ? candidate.collapsed : fallback.collapsed,
    }
    if (finite(fallback.width)) {
      window.width = clampMinimapWidth(
        finite(candidate?.width) ? candidate.width : fallback.width
      )
    }
    windows[id] = window
  }

  return {
    version: COCKPIT_LAYOUT_VERSION,
    locked: boolean(saved.locked) ? saved.locked : defaults.locked,
    windows,
  }
}

export class CockpitWindowManager {
  constructor({
    root,
    playerId,
    storage,
    windowTarget = globalThis.window,
    documentTarget = globalThis.document,
    definitions = DEFAULT_COCKPIT_WINDOWS,
    compactBreakpoint = COCKPIT_COMPACT_BREAKPOINT,
  }) {
    this.root = root
    try {
      this.storage = storage === undefined ? globalThis.localStorage : storage
    } catch (_error) {
      this.storage = null
    }
    this.windowTarget = windowTarget
    this.documentTarget = documentTarget
    this.definitions = definitions
    this.compactBreakpoint = compactBreakpoint
    this.storageKey = cockpitStorageKey(playerId)
    this.windows = new Map()
    this.listeners = []
    this.drag = null
    this.topLayer = 30
    this.compact = false

    for (const element of root?.querySelectorAll?.("[data-cockpit-window]") || []) {
      const id = element.dataset.cockpitWindow
      if (definitions[id] && !this.windows.has(id)) this.windows.set(id, element)
    }

    this.onResize = () => this.handleResize()
    this.onWindowBlur = () => this.finishDrag(false)
    this.onVisibilityChange = () => {
      if (this.documentTarget.hidden) this.finishDrag(false)
    }
  }

  start() {
    if (!this.root || this.started) return this
    this.started = true
    this.defaults = this.createDefaultLayout()
    this.layout = this.restoreLayout()
    this.bindControls()
    this.applyLayout()
    this.listen(this.windowTarget, "resize", this.onResize)
    this.listen(this.windowTarget, "blur", this.onWindowBlur)
    this.listen(this.documentTarget, "visibilitychange", this.onVisibilityChange)
    this.handleResize(false)
    return this
  }

  destroy() {
    if (!this.started) return
    this.finishDrag(false)
    for (const {target, type, listener, options} of this.listeners) {
      target.removeEventListener(type, listener, options)
    }
    this.listeners = []
    this.started = false
  }

  createDefaultLayout() {
    const viewport = this.viewport()
    const windows = {}

    for (const [id, element] of this.windows) {
      const definition = this.definitions[id]
      const measured = this.measure(element)
      const width = finite(definition.width)
        ? clampMinimapWidth(definition.width, viewport.width)
        : null
      const size = width === null ? measured : {...measured, width}
      const position = defaultWindowPosition(definition, size, viewport)
      windows[id] = {
        ...clampWindowPosition(position, size, viewport),
        visible: definition.visible,
        collapsed: definition.collapsed,
        ...(width === null ? {} : {width}),
      }
    }

    return {version: COCKPIT_LAYOUT_VERSION, locked: true, windows}
  }

  restoreLayout() {
    try {
      const saved = JSON.parse(this.storage?.getItem?.(this.storageKey) || "null")
      return sanitizeCockpitLayout(saved, this.defaults)
    } catch (_error) {
      return this.defaults
    }
  }

  persist() {
    try {
      this.storage?.setItem?.(this.storageKey, JSON.stringify(this.layout))
    } catch (_error) {
      // Private browsing and quota failures must never interrupt game input.
    }
  }

  reset() {
    this.defaults = this.createDefaultLayout()
    this.layout = this.defaults
    this.applyLayout()
    this.persist()
  }

  toggleLock() {
    this.setLocked(!this.layout.locked)
  }

  setLocked(locked) {
    this.layout.locked = Boolean(locked)
    if (this.layout.locked) this.finishDrag(false)
    this.applyLockState()
    this.persist()
  }

  toggleCollapsed(id) {
    const state = this.layout.windows[id]
    if (!state) return
    state.collapsed = !state.collapsed
    this.applyWindowState(id)
    this.clampWindow(id)
    this.persist()
  }

  setVisible(id, visible) {
    const state = this.layout.windows[id]
    if (!state) return
    state.visible = Boolean(visible)
    this.applyWindowState(id)
    if (state.visible) this.clampWindow(id)
    this.updateVisibilityControls()
    this.persist()
  }

  windowContentInteractive(id) {
    const state = this.layout?.windows?.[id]
    const element = this.windows.get(id)

    return Boolean(
      this.layout?.locked &&
      state?.visible &&
      !state.collapsed &&
      element &&
      !element.hidden
    )
  }

  focusWindow(id) {
    const element = this.windows.get(id)
    if (!element) return
    this.topLayer += 1
    element.style.zIndex = String(this.topLayer)
    for (const candidate of this.windows.values()) {
      candidate.classList.toggle("is-focused", candidate === element)
    }
  }

  handleResize(persist = true) {
    const viewport = this.viewport()
    const compact = viewport.width < this.compactBreakpoint || viewport.height < 620
    this.compact = compact
    this.root.classList.toggle("is-compact", compact)
    this.root.dataset.cockpitMode = compact ? "docked" : "floating"
    this.clampMinimapToViewport(viewport)

    if (!compact) this.clampAll()
    if (persist) this.persist()
  }

  resizeMinimap(direction) {
    const state = this.layout.windows.minimap
    const element = this.windows.get("minimap")
    if (!state || !element || !finite(direction) || direction === 0) return

    const viewport = this.viewport()
    const previousWidth = clampMinimapWidth(state.width, viewport.width)
    const nextWidth = clampMinimapWidth(
      previousWidth + Math.sign(direction) * MINIMAP_WIDTH_STEP,
      viewport.width
    )

    state.width = nextWidth
    if (!this.compact && nextWidth !== previousWidth) {
      state.x -= nextWidth - previousWidth
    }
    this.applyMinimapWidth()
    if (!this.compact) this.clampWindow("minimap")
    this.updateMinimapSizeControls()
    if (nextWidth !== previousWidth) this.persist()
  }

  clampMinimapToViewport(viewport = this.viewport()) {
    const state = this.layout.windows.minimap
    if (!state) return

    state.width = clampMinimapWidth(state.width, viewport.width)
    this.applyMinimapWidth()
    this.updateMinimapSizeControls()
  }

  clampAll() {
    for (const id of this.windows.keys()) this.clampWindow(id)
  }

  clampWindow(id) {
    const state = this.layout.windows[id]
    const element = this.windows.get(id)
    if (!state || !element || !state.visible) return

    const position = clampWindowPosition(state, this.measureWindow(id, element), this.viewport())
    state.x = position.x
    state.y = position.y
    this.applyPosition(element, state)
  }

  applyLayout() {
    this.applyLockState()
    this.applyMinimapWidth()
    for (const id of this.windows.keys()) this.applyWindowState(id)
    this.updateVisibilityControls()
    this.updateMinimapSizeControls()
  }

  applyLockState() {
    const unlocked = !this.layout.locked
    this.root.classList.toggle("is-unlocked", unlocked)
    this.root.dataset.hudLocked = String(this.layout.locked)

    const button = this.root.querySelector("[data-cockpit-lock-toggle]")
    const label = button?.querySelector?.("[data-cockpit-lock-label]")
    if (button) {
      button.setAttribute("aria-pressed", String(unlocked))
      button.setAttribute("aria-label", unlocked ? "Lock HUD" : "Unlock HUD")
    }
    if (label) label.textContent = unlocked ? "Lock HUD" : "Unlock HUD"
  }

  applyWindowState(id) {
    const element = this.windows.get(id)
    const state = this.layout.windows[id]
    if (!element || !state) return

    element.hidden = !state.visible
    element.classList.toggle("is-collapsed", state.collapsed)
    element.dataset.cockpitCollapsed = String(state.collapsed)
    this.applyPosition(element, state)

    const collapse = element.querySelector("[data-cockpit-collapse]")
    if (collapse) {
      collapse.setAttribute("aria-expanded", String(!state.collapsed))
      collapse.setAttribute(
        "aria-label",
        state.collapsed
          ? `Expand ${id.replaceAll("_", " ")}`
          : `Collapse ${id.replaceAll("_", " ")}`
      )
    }
  }

  applyPosition(element, state) {
    element.style.transform = `translate3d(${Math.round(state.x)}px, ${Math.round(state.y)}px, 0)`
  }

  applyMinimapWidth() {
    const element = this.windows.get("minimap")
    const width = this.layout?.windows?.minimap?.width
    if (!element || !finite(width)) return

    element.style.setProperty("--cockpit-minimap-width", `${Math.round(width)}px`)
  }

  updateMinimapSizeControls() {
    const element = this.windows.get("minimap")
    const state = this.layout?.windows?.minimap
    if (!element || !state) return

    const width = clampMinimapWidth(state.width, this.viewport().width)
    const maximum = clampMinimapWidth(MINIMAP_MAX_WIDTH, this.viewport().width)
    for (const control of element.querySelectorAll("[data-cockpit-minimap-resize]")) {
      const decrease = control.dataset.cockpitMinimapResize === "decrease"
      const disabled = decrease ? width <= MINIMAP_MIN_WIDTH : width >= maximum
      control.disabled = disabled
      control.setAttribute("aria-disabled", String(disabled))
    }
  }

  updateVisibilityControls() {
    for (const control of this.root.querySelectorAll("[data-cockpit-visibility]")) {
      const id = control.dataset.cockpitVisibility
      const visible = Boolean(this.layout.windows[id]?.visible)
      control.setAttribute("aria-pressed", String(visible))
      control.classList.toggle("is-visible", visible)
      const status = control.querySelector?.("[data-cockpit-visibility-status]")
      if (status) status.textContent = visible ? "Visible" : "Hidden"
    }
  }

  bindControls() {
    for (const [id, element] of this.windows) {
      const header = element.querySelector("[data-cockpit-drag-handle]")
      const collapse = element.querySelector("[data-cockpit-collapse]")
      const hide = element.querySelector("[data-cockpit-hide]")
      const minimapResize = element.querySelectorAll("[data-cockpit-minimap-resize]")

      this.listen(element, "pointerdown", event => {
        event.stopPropagation()
        this.focusWindow(id)
      })
      this.listen(element, "click", event => event.stopPropagation())
      this.listen(element, "contextmenu", event => event.stopPropagation())
      if (header) {
        this.listen(header, "pointerdown", event => this.beginDrag(id, event))
        this.listen(header, "pointermove", event => this.moveDrag(event))
        this.listen(header, "pointerup", event => this.endDrag(event))
        this.listen(header, "pointercancel", event => this.cancelDrag(event))
        this.listen(header, "lostpointercapture", event => this.cancelDrag(event))
        this.listen(header, "keydown", event => this.moveWithKeyboard(id, event))
      }
      if (collapse) this.listen(collapse, "click", () => this.toggleCollapsed(id))
      if (hide) this.listen(hide, "click", () => this.setVisible(id, false))
      for (const control of minimapResize) {
        const direction = control.dataset.cockpitMinimapResize === "increase" ? 1 : -1
        this.listen(control, "click", () => this.resizeMinimap(direction))
      }
    }

    const lock = this.root.querySelector("[data-cockpit-lock-toggle]")
    const reset = this.root.querySelector("[data-cockpit-reset]")
    const menu = this.root.querySelector("[data-cockpit-menu]")
    const menuToggle = this.root.querySelector("[data-cockpit-menu-toggle]")
    if (lock) this.listen(lock, "click", () => this.toggleLock())
    if (reset) this.listen(reset, "click", () => this.reset())
    if (menuToggle && menu) {
      this.listen(menuToggle, "click", () => {
        const open = menu.hidden
        menu.hidden = !open
        menuToggle.setAttribute("aria-expanded", String(open))
        menuToggle.setAttribute(
          "aria-label",
          open ? "Close cockpit window menu" : "Open cockpit window menu"
        )
      })
    }
    for (const control of this.root.querySelectorAll("[data-cockpit-visibility]")) {
      this.listen(control, "click", () => {
        const id = control.dataset.cockpitVisibility
        this.setVisible(id, !this.layout.windows[id]?.visible)
      })
    }
  }

  beginDrag(id, event) {
    if (this.layout.locked || this.compact || event.button !== 0 || event.target?.closest?.("button")) return

    const state = this.layout.windows[id]
    const handle = event.currentTarget
    event.preventDefault()
    event.stopPropagation()
    this.focusWindow(id)
    this.drag = {
      id,
      pointerId: event.pointerId,
      handle,
      originX: state.x,
      originY: state.y,
      pointerX: event.clientX,
      pointerY: event.clientY,
      moved: false,
    }
    this.windows.get(id)?.classList.add("is-dragging")

    try {
      handle.setPointerCapture(event.pointerId)
    } catch (_error) {
      // Window blur and pointer cancellation still clean up an unavailable capture.
    }
  }

  moveDrag(event) {
    if (!this.drag || event.pointerId !== this.drag.pointerId) return
    const state = this.layout.windows[this.drag.id]
    const element = this.windows.get(this.drag.id)
    const proposed = {
      x: this.drag.originX + event.clientX - this.drag.pointerX,
      y: this.drag.originY + event.clientY - this.drag.pointerY,
    }
    const position = clampWindowPosition(proposed, this.measure(element), this.viewport())
    state.x = position.x
    state.y = position.y
    this.drag.moved = true
    this.applyPosition(element, state)
    event.preventDefault()
    event.stopPropagation()
  }

  endDrag(event) {
    if (this.drag && event.pointerId === this.drag.pointerId) this.finishDrag(true)
  }

  cancelDrag(event) {
    if (this.drag && event.pointerId === this.drag.pointerId) this.finishDrag(false)
  }

  finishDrag(persist) {
    if (!this.drag) return
    const {handle, pointerId, id, moved} = this.drag
    this.drag = null
    this.windows.get(id)?.classList.remove("is-dragging")
    try {
      if (!handle.hasPointerCapture || handle.hasPointerCapture(pointerId)) {
        handle.releasePointerCapture(pointerId)
      }
    } catch (_error) {
      // Capture may already have been released by the browser.
    }
    if (persist && moved) this.persist()
  }

  moveWithKeyboard(id, event) {
    if (this.layout.locked || this.compact || event.target?.closest?.("button")) return
    const directions = {
      ArrowLeft: [-1, 0],
      ArrowRight: [1, 0],
      ArrowUp: [0, -1],
      ArrowDown: [0, 1],
    }
    const direction = directions[event.code]
    if (!direction) return

    const step = event.shiftKey ? 10 : 2
    const state = this.layout.windows[id]
    const position = clampWindowPosition(
      {x: state.x + direction[0] * step, y: state.y + direction[1] * step},
      this.measureWindow(id, this.windows.get(id)),
      this.viewport()
    )
    state.x = position.x
    state.y = position.y
    this.applyPosition(this.windows.get(id), state)
    this.focusWindow(id)
    this.persist()
    event.preventDefault()
    event.stopPropagation()
  }

  viewport() {
    return {
      width: Math.max(320, Number(this.windowTarget?.innerWidth) || 320),
      height: Math.max(320, Number(this.windowTarget?.innerHeight) || 320),
    }
  }

  measure(element) {
    const rect = element?.getBoundingClientRect?.() || {}
    return {
      width: Number(rect.width) || Number(element?.offsetWidth) || 320,
      height: Number(rect.height) || Number(element?.offsetHeight) || 220,
    }
  }

  measureWindow(id, element) {
    const measured = this.measure(element)
    const width = this.layout?.windows?.[id]?.width
    return finite(width) ? {...measured, width} : measured
  }

  listen(target, type, listener, options) {
    if (!target?.addEventListener) return
    target.addEventListener(type, listener, options)
    this.listeners.push({target, type, listener, options})
  }
}
