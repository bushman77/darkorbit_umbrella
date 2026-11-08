// A single reason for disabled flight input. Presentation and control guards
// share this predicate; rendering the cockpit never silently changes propulsion.
export function flightInputState({
  atlasOpen = false, docked = false, encounterHeld = false,
  cruiseLocked = false, sectorJoined = false, ship = null,
} = {}) {
  if (atlasOpen) return "atlas"
  if (docked) return "docked"
  if (!sectorJoined) return "disconnected"
  if (!ship) return "synchronizing"
  if (ship.status === "destroyed") return "destroyed"
  if (encounterHeld) return "encounter"
  if (cruiseLocked) return "cruise"
  return "ready"
}

export const FLIGHT_INPUT_LABELS = Object.freeze({
  docked: "DOCKED · LAUNCH FROM THE STATION TO ENABLE FLIGHT",
  encounter: "ENCOUNTER HOLD · CHOOSE HAIL, ENGAGE OR CONTINUE",
  cruise: "AUTOPILOT ACTIVE · MANUAL FLIGHT CONTROLS DISABLED",
  disconnected: "FLIGHT INPUT WAITING · SECTOR LINK NOT JOINED",
  synchronizing: "FLIGHT INPUT WAITING · SHIP STATE SYNCHRONIZING",
  destroyed: "SHIP DESTROYED · RECONNECT TO RESPAWN",
})
