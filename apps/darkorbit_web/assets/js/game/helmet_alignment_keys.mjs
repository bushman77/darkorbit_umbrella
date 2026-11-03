// Phone HMD calibration is captured from the laptop cockpit only.
// Left/right move the pair of optical images together/apart (including
// convergence inside fixed non-overlapping viewports below zero).
// F6 / Ctrl+F6 retain the separate simulated interpupillary distance.
export function helmetAlignmentKeyIntent(event, {active = false, typing = false} = {}) {
  if (!active || typing || event.defaultPrevented ||
      event.altKey || event.metaKey || event.shiftKey) return null

  const key = event.code || event.key
  if ((key === "ArrowLeft" || key === "ArrowRight") && !event.ctrlKey) {
    return {axis: "gap", direction: key === "ArrowLeft" ? -1 : 1}
  }

  if (key === "F6" && !event.repeat) {
    return {axis: "eye_sep", direction: event.ctrlKey ? 1 : -1}
  }

  return null
}
