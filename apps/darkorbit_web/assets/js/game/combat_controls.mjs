const HOTBAR_CODES = Object.freeze({
  Digit1: 1,
  Digit2: 2,
  Digit3: 3,
  Digit4: 4,
  Digit5: 5,
  Digit6: 6,
  Digit7: 7,
  Digit8: 8,
  Digit9: 9,
  Digit0: 10,
})

export const hotbarSlotForCode = code => HOTBAR_CODES[code] || null

export const inputControl = target => Boolean(
  target?.matches?.(
    "input, textarea, select, button, [contenteditable='true'], [data-cockpit-drag-handle]"
  ) ||
  target?.isContentEditable
)

export const gameplayTypingTarget = target => Boolean(
  target?.isContentEditable ||
  ["INPUT", "TEXTAREA", "SELECT"].includes(target?.tagName?.toUpperCase?.()) ||
  target?.matches?.("input, textarea, select, [contenteditable='true']")
)

export const manualLaserPointerIntent = (event, active) =>
  Boolean(active && event?.button === 2 && !event.ctrlKey && !event.altKey &&
    !event.metaKey && !event.shiftKey)

export const combatKeyIntent = event => {
  // Manual laser is exclusively RMB on the cockpit viewport. Space remains
  // unassigned so it cannot accidentally activate weapons.
  if (event.repeat || inputControl(event.target)) {
    return null
  }

  if (["ControlLeft", "ControlRight"].includes(event.code)) {
    return event.altKey || event.metaKey || event.shiftKey ? null : {type: "toggle_laser"}
  }

  if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return null

  if (event.code === "Escape") return {type: "disengage"}
  if (event.code === "KeyL") return {type: "toggle_laser"}
  if (event.code === "KeyT") return {type: "target_nearest"}

  const slot = hotbarSlotForCode(event.code)
  return slot ? {type: "activate_slot", slot} : null
}

export const hotbarActionActive = (action, laserEngaged) => Boolean(
  laserEngaged &&
  action?.type === "ammunition" &&
  action?.activationMode === "toggle"
)

export const angleToTarget = (source, target) => {
  if (!source || !target) return null
  return Math.atan2(target.y - source.y, target.x - source.x)
}

const wrappedAngleDelta = (from, to) => Math.atan2(Math.sin(to - from), Math.cos(to - from))

export const smoothAngle = (current, desired, blend) => {
  if (!Number.isFinite(desired)) return current
  if (!Number.isFinite(current)) return desired
  return current + wrappedAngleDelta(current, desired) * Math.min(1, Math.max(0, blend))
}

export const desiredEntityAngle = (entity, entities) => {
  const combatId = entity?.engagedTargetId ||
    (entity?.kind === "npc" ? entity.targetId : null)
  const combatTarget = combatId && entities.get(combatId)
  const combatAngle = angleToTarget(entity?.render, combatTarget?.render)
  return combatAngle ?? entity?.navigationAngle ?? entity?.angle ?? -Math.PI / 2
}
