// Physical phone headset buttons generally generate a touchscreen press.
// Only consume taps while the actual SBS cockpit is rendering. Setup UI and
// future explicit controls must retain their ordinary click behavior.
export function headsetScreenTapRecenterAllowed({
  mode, immersiveReady, running, setupVisible, target,
}) {
  if (mode !== "combat" || !immersiveReady || !running || setupVisible || !target) {
    return false
  }
  return !target.closest?.("button, a, input, select, textarea, [role='button'], #helmet-setup")
}
