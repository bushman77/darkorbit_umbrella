// Read-only MapServer docking hold visualization: client time never
// authorizes docking or changes the server's required dwell period.
export function dockingHoldFromEvent(data, now = performance.now()) {
  if (!data || !Number.isInteger(data.started_tick) || data.started_tick < 0 ||
      !Number.isFinite(data.duration_ms) || data.duration_ms <= 0 ||
      !Number.isFinite(data.remaining_ms) || data.remaining_ms < 0 ||
      data.remaining_ms > data.duration_ms) return null
  return {
    startedTick: data.started_tick,
    deadline: now + data.remaining_ms,
  }
}

export function syncDockingHold(previous, world, playerId, now = performance.now()) {
  if (!Array.isArray(world?.docking_holds)) return previous
  const hold = playerId == null ? null : world.docking_holds.find(
    entry => String(entry.entity_id) === String(playerId))
  if (!hold) return null
  // Normal world snapshots arrive each tick. Do not restart the countdown.
  if (previous && previous.startedTick === hold.started_tick) return previous
  if (!Number.isInteger(world.tick) || !Number.isInteger(world.tick_ms) ||
      world.tick_ms <= 0 || world.tick < hold.started_tick ||
      !Number.isFinite(hold.duration_ms) || hold.duration_ms <= 0) return null
  // Reconstruct the remaining hold from static metadata in the world.
  // There is no per-tick change to docking_holds in server deltas.
  const remaining_ms = Math.max(0,
    hold.duration_ms - (world.tick - hold.started_tick) * world.tick_ms)
  return dockingHoldFromEvent({...hold, remaining_ms}, now)
}

export function dockingSeconds(hold, now = performance.now()) {
  if (!hold || !Number.isFinite(hold.deadline)) return null
  return Math.max(0, Math.ceil((hold.deadline - now) / 1_000))
}
