// Visually smooth authoritative yaw/pitch/roll across 100 ms server ticks.
// Angles use the shortest wrapped path through +/-PI. All camera motion is
// presentation only: no client-generated positions or server inputs.
const AXES = ["yaw", "pitch", "roll"]
export const wrapAngle = a => Math.atan2(Math.sin(a), Math.cos(a))
export const angularDelta = (start, end) => wrapAngle(end - start)

export function smoothAttitude(current, target, deltaSeconds, settleSeconds = 0.085) {
  if (!current || !target) return target || current
  const elapsed = Math.max(0, Math.min(deltaSeconds, 0.15))
  const weight = 1 - Math.exp(-elapsed / settleSeconds)

  return Object.fromEntries(AXES.map(axis => {
    const start = Number.isFinite(current[axis]) ? current[axis] : 0
    const finish = Number.isFinite(target[axis]) ? target[axis] : start
    const delta = angularDelta(start, finish)
    return [axis, wrapAngle(start + delta * weight)]
  }))
}
