// These lightweight presentation selectors never authorize station dialogue.
// The world snapshot carries the attendant roster from MapServer, while
// the server separately verifies the player's current room and distance.
export const STATION_TALK_RANGE = 12

export function nearestStationAttendant(position, attendants,
  radius = STATION_TALK_RANGE) {
  if (!position || typeof position.room_id !== "string" ||
      !Number.isFinite(position.x) || !Number.isFinite(position.z) ||
      !Array.isArray(attendants)) return null
  let nearest = null
  let closest = radius * radius
  for (const npc of attendants) {
    if (!npc || typeof npc.id !== "string" ||
        npc.room_id !== position.room_id ||
        !Number.isFinite(npc.x) || !Number.isFinite(npc.z)) continue
    const dx = npc.x - position.x
    const dz = npc.z - position.z
    const distance = dx * dx + dz * dz
    if (distance <= closest) {
      closest = distance
      nearest = npc
    }
  }
  return nearest
}
