// Paired phone only: independent of the laptop HUD and target selection.
// The server sends visual-only, pilot-scoped surrender state.
export function renderHelmetSurrender(root, payload) {
  if (!root) return
  const surrendered = payload?.surrendered === true
  root.hidden = !surrendered
  if (!surrendered) return

  const name = typeof payload.call_sign === "string" && payload.call_sign.trim()
    ? payload.call_sign.slice(0, 30) : "CONTACT"
  for (const node of root.querySelectorAll("[data-helmet-surrender-name]")) {
    node.textContent = name
  }
}

// Snapshot fallback: resume the same banner after reconnect or a missed event.
// Do not use a laptop selection, navigator flag, or anyone else's NPC.
export function helmetSurrenderFromEntities(entities, pilotId) {
  if (pilotId == null) return {surrendered: false}
  const suffix = "-" + pilotId
  for (const npc of entities?.values?.() || []) {
    if (npc.kind === "npc" && npc.state === "surrendered" &&
        npc.status !== "destroyed" && typeof npc.npcTypeId === "string" &&
        npc.npcTypeId.startsWith("solar-") && npc.npcTypeId.endsWith(suffix)) {
      return {surrendered: true, call_sign: npc.displayName || "CONTACT"}
    }
  }
  return {surrendered: false}
}
