// Physical pixel-space halves for phone SBS. The optional optical gap
// separates the eye images and allows fitting different VR headset lenses.
export function stereoViewports(width, height, requestedGap = 0) {
  const w = Math.max(2, Math.floor(Number(width) || 2))
  const h = Math.max(1, Math.floor(Number(height) || 1))
  const gap = Math.max(0, Math.min(Math.floor(Number(requestedGap) || 0), w - 2))
  const leftWidth = Math.floor((w - gap) / 2)
  const rightX = leftWidth + gap
  const rightWidth = w - rightX
  return {
    gap,
    eyeAspect: (leftWidth + rightWidth) / (2 * h),
    left: {x: 0, y: 0, width: leftWidth, height: h},
    right: {x: rightX, y: 0, width: rightWidth, height: h},
  }
}

// A negative "center gap" represents an inward optical image shift rather
// than overlapping the physical eye viewports. In a perspective projection
// centered geometry has NDC x = -projectionMatrix.elements[8]. Decrease that
// term for the left eye (moves the view right), increase for the right eye
// (moves it left). -2px gap shifts each image inward by 1 CSS pixel.
export function inwardStereoProjectionOffset(signedGap, eyeWidth) {
  const inwardPerEyePx = Math.max(0, -(Number(signedGap) || 0)) / 2
  return 2 * inwardPerEyePx / Math.max(1, eyeWidth)
}


// The StereoCamera caches its per-eye projection matrices and may skip
// recalculating them on the next frame. Mutating elements[8] permanently
// causes the optical offset to accumulate every animation frame: the two
// views appear to scroll sideways even when the ship and inputs are idle.
//
// Apply the optical correction only for the scope of one render/raycast and
// ALWAYS restore the underlying matrices, including on a WebGL exception.
export function applyTransientStereoOffset(leftProjection, rightProjection, signedGap, eyeWidth) {
  const shift = inwardStereoProjectionOffset(signedGap, eyeWidth)
  const left = leftProjection.elements
  const right = rightProjection.elements
  const baseLeft = left[8]
  const baseRight = right[8]
  if (shift !== 0) {
    left[8] = baseLeft - shift
    right[8] = baseRight + shift
  }
  let restored = false
  return () => {
    if (restored) return
    restored = true
    left[8] = baseLeft
    right[8] = baseRight
  }
}
