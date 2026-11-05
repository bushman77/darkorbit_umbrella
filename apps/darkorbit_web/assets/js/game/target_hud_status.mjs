// Presentation only. The server owns NPC surrender decisions.
export const surrenderedTargetLabel = entity =>
  entity?.kind === "npc" && entity.state === "surrendered"
    ? "SURRENDERED · " + String(entity.displayName || "CONTACT").slice(0, 19)
    : null

// An active solar tactical opponent belongs to the pilot whose ID is
// embedded in its authoritative NPC type ID (solar-<class>-<pilot_id>).
// No target lock is required, and other pilots' NPCs are excluded.
export function surrenderedHudLabel(client) {
  const selected = client?.entities?.get(client.selectedTargetId)
  const selectedLabel = surrenderedTargetLabel(selected)
  if (selectedLabel) return selectedLabel

  const navigation = client?.navComputer?.solarNavigation
  if (!navigation?.tactical_encounter && navigation?.tactical_active !== true)
    return null
  if (client?.selfId == null) return null

  const pilotSuffix = "-" + client.selfId
  for (const entity of client.entities?.values() || []) {
    if (typeof entity.npcTypeId === "string" &&
        entity.npcTypeId.startsWith("solar-") &&
        entity.npcTypeId.endsWith(pilotSuffix)) {
      const label = surrenderedTargetLabel(entity)
      if (label) return label
    }
  }
  return null
}
