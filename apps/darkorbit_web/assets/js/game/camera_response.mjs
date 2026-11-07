// Presentation-only camera response tuning. The server remains the sole owner
// of ship orientation; this only controls how quickly frames catch up to the
// latest authoritative quaternion after input updates.
export const STANDARD_CAMERA_SETTLE_SECONDS = 0.085
export const POINTER_LOCK_CAMERA_SETTLE_SECONDS = 0.025

export const cameraSettleSeconds = ({ownShip = false, pointerLocked = false} = {}) =>
  ownShip && pointerLocked
    ? POINTER_LOCK_CAMERA_SETTLE_SECONDS
    : STANDARD_CAMERA_SETTLE_SECONDS
