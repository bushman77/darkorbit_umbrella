// Only flight presentation modes. The overhead atlas is a separate dialog.
export const FLIGHT_DISPLAY_MODES = Object.freeze(["3d", "sbs"])

export const validFlightMode = mode => FLIGHT_DISPLAY_MODES.includes(mode)

export function nextFlightMode(current) {
  return current === "sbs" ? "3d" : "sbs"
}
