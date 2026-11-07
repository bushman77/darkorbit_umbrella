// Pure read-only view adapter: two matching stereo eye alerts.
// Does not accept commands or mutate any game state.
export function renderHelmetEncounter(root, payload) {
  if (!root) return

  const encounter = payload?.paused === true && payload.encounter?.id
    ? payload.encounter
    : null
  root.hidden = !encounter
  if (!encounter) return

  const name = typeof encounter.call_sign === "string"
    ? encounter.call_sign : "Unidentified vessel"
  const kind = encounter.classification === "hostile_contact"
    ? "HOSTILE CONTACT"
    : encounter.classification === "patrol_attention"
      ? "FACTION PATROL"
      : "NEUTRAL CONTACT"

  for (const title of root.querySelectorAll("[data-helmet-encounter-title]")) {
    title.textContent = name
  }
  for (const label of root.querySelectorAll("[data-helmet-encounter-faction]")) {
    label.textContent = "FACTION / " +
      String(encounter.faction_name || "Unregistered Organization")
  }
  for (const status of root.querySelectorAll("[data-helmet-encounter-kind]")) {
    status.textContent = kind + " · CRUISE PAUSED"
  }
}
