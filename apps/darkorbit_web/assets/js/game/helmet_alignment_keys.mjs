// Calibrate the paired phone from the laptop keyboard, not an overlay.
// One physical press = one adjustment; key auto-repeat is NEVER accepted.
// Reserve arrows/F6 in cockpit mode to prevent browser page scrolling.

export function helmetAlignmentShortcut(event, {active = false, typing = false} = {}) {
  if (!active || typing || event.defaultPrevented ||
      event.altKey || event.metaKey || event.shiftKey) return false

  const key = event.code || event.key
  return (key === "ArrowLeft" || key === "ArrowRight")
    ? !event.ctrlKey
    : key === "F6"
}

export function helmetAlignmentKeyIntent(event, options = {}) {
  if (!helmetAlignmentShortcut(event, options) || event.repeat) return null

  const key = event.code || event.key
  if (key === "ArrowLeft" || key === "ArrowRight")
    return {axis: "gap", direction: key === "ArrowLeft" ? -1 : 1}

  return {axis: "eye_sep", direction: event.ctrlKey ? 1 : -1}
}

// A latch protects against browsers and keyboard adapters that occasionally
// send repeated keydown events without setting event.repeat correctly.
export class HelmetAlignmentKeyGate {
  constructor() { this.held = new Set() }

  keyDown(event, options = {}) {
    if (!helmetAlignmentShortcut(event, options))
      return {reserved: false, intent: null}

    const key = event.code || event.key
    if (event.repeat || this.held.has(key))
      return {reserved: true, intent: null}

    this.held.add(key)
    return {reserved: true, intent: helmetAlignmentKeyIntent(event, options)}
  }

  keyUp(event) { this.held.delete(event.code || event.key) }
  release() { this.held.clear() }
}
