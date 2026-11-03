// Phone-owned calibration. The laptop sends relative, validated adjustments.
export const HELMET_GAP_STEP = 2
export const HELMET_SEPARATION_STEP = 1
// Negative values shift both projections inward while keeping the physical
// SBS eye viewports disjoint. Positive values create a black center strip.
export const HELMET_GAP_MIN = -160
export const HELMET_GAP_MAX = 80

const clamp = (number, min, max) => Math.min(max, Math.max(min, number))

export function adjustedHelmetAlignment(current, axis, direction) {
  if ((axis !== "gap" && axis !== "eye_sep") || ![-1, 1].includes(direction)) {
    return null
  }
  const eyeGapPx = clamp(Math.round(Number(current?.eyeGapPx) || 0), HELMET_GAP_MIN, HELMET_GAP_MAX)
  const eyeSepMm = clamp(Math.round(Number(current?.eyeSepMm) || 64), 40, 85)

  return {
    eyeGapPx: axis === "gap"
      ? clamp(eyeGapPx + direction * HELMET_GAP_STEP, HELMET_GAP_MIN, HELMET_GAP_MAX)
      : eyeGapPx,
    eyeSepMm: axis === "eye_sep"
      ? clamp(eyeSepMm + direction * HELMET_SEPARATION_STEP, 40, 85)
      : eyeSepMm,
  }
}
