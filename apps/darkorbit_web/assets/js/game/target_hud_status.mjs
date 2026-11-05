// Presentation only. The server owns NPC surrender decisions.
export const surrenderedTargetLabel = entity =>
  entity?.kind === "npc" && entity.state === "surrendered"
    ? "SURRENDERED · " + String(entity.displayName || "CONTACT").slice(0, 19)
    : null
