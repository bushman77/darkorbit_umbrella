// F5/F6 are deliberately intercepted only while an HMD is active in combat.
// Some browsers reserve Ctrl+F5 for hard reload despite preventDefault;
// the cockpit also offers clickable controls as a fallback.
export function helmetAlignmentKeyIntent(event, {active = false, typing = false} = {}) {
  if (!active || typing || event.defaultPrevented || event.repeat ||
      event.altKey || event.metaKey || event.shiftKey) return null

  const key = event.code || event.key
  if (key !== "F5" && key !== "F6") return null

  return {
    axis: key === "F5" ? "gap" : "eye_sep",
    direction: event.ctrlKey ? 1 : -1,
  }
}
