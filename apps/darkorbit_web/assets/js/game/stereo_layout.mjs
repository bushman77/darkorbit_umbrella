// Geometry sizing expressed in camera-local units. Kept pure for viewport regressions.
export const HUD_GEOMETRY = Object.freeze({
  width: 2.15,
  height: 0.54,
  depth: 2.5,
  centerY: -0.67,
})

// Limit the physical dashboard to 75% of the horizontal eye view, especially
// when each SBS eye has a narrow aspect ratio.
export function cockpitHudFit(aspect, verticalFovDegrees = 70) {
  if (!Number.isFinite(aspect) || aspect <= 0) return null
  if (!Number.isFinite(verticalFovDegrees) || verticalFovDegrees <= 0 || verticalFovDegrees >= 180) return null

  const verticalSpan = 2 * HUD_GEOMETRY.depth * Math.tan(verticalFovDegrees * Math.PI / 360)
  const horizontalSpan = verticalSpan * aspect
  const scale = Math.min(1, horizontalSpan * 0.75 / HUD_GEOMETRY.width)
  const halfHeight = HUD_GEOMETRY.height * scale / 2
  return {
    scale,
    widthFraction: HUD_GEOMETRY.width * scale / horizontalSpan,
    topFraction: 0.5 - (HUD_GEOMETRY.centerY + halfHeight) / verticalSpan,
    bottomFraction: 0.5 - (HUD_GEOMETRY.centerY - halfHeight) / verticalSpan,
  }
}
