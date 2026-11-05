// Presentation only. The server owns NPC surrender decisions.
export const surrenderedTargetLabel = entity =>
  entity?.kind === "npc" && entity.state === "surrendered"
    ? "SURRENDERED · " + String(entity.displayName || "CONTACT").slice(0, 19)
    : null

// A tactical Scow belongs to the pilot whose ID is embedded in its
// authoritative NPC type ID. A target lock is NOT required for surrender
// telemetry, and another pilot's surrendered Scow must not be shown.
export function surrenderedHudLabel(client) {
  const selected = client?.entities?.get(client.selectedTargetId)
  const selectedLabel = surrenderedTargetLabel(selected)
  if (selectedLabel) return selectedLabel

  const navigation = client?.navComputer?.solarNavigation
  if (!navigation?.tactical_encounter && navigation?.tactical_active !== true)
    return null
  if (client?.selfId == null) return null

  const ownedScowId = "solar-scow-" + client.selfId
  for (const entity of client.entities?.values() || []) {
    if (entity.npcTypeId === ownedScowId) return surrenderedTargetLabel(entity)
  }
  return null
}
