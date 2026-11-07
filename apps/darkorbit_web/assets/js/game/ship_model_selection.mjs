import {isDartModelId} from "./dart_model.mjs"
import {isScowModelId} from "./scow_model.mjs"

// Prefer the actual server-spawned NPC type. The explicit ship class is a
// fallback for future map snapshots and avoids client-specific prefix guesses.
export function npcVisualClass(npcTypeId, shipClass = null) {
  if (isScowModelId(npcTypeId)) return "scow"
  if (isDartModelId(npcTypeId)) return "dart"
  if (shipClass === "scow" || shipClass === "dart") return shipClass
  return "generic"
}
