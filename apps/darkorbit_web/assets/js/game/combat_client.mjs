export const entityKey = id => String(id)

export const healthPercent = (current, maximum) => {
  if (!Number.isFinite(current) || !Number.isFinite(maximum) || maximum <= 0) return 0
  return Math.min(100, Math.max(0, (current / maximum) * 100))
}

export const selectableNpc = entity =>
  entity?.kind === "npc" && entity.status !== "destroyed" && Number(entity.hull) > 0

const distanceSquared = (left, right) => {
  const deltaX = left.x - right.x
  const deltaY = left.y - right.y
  return deltaX * deltaX + deltaY * deltaY
}

export const nearestNpc = (entities, origin) => {
  if (!origin) return null

  return [...entities]
    .filter(selectableNpc)
    .sort((left, right) => {
      const distance = distanceSquared(left.target, origin) - distanceSquared(right.target, origin)
      return distance || entityKey(left.id).localeCompare(entityKey(right.id))
    })[0] || null
}

export const findNpcAtScreenPoint = (
  entities,
  point,
  worldToScreen,
  dimensionsForEntity = () => ({width: 84, height: 84})
) => {
  return [...entities]
    .filter(selectableNpc)
    .map(entity => {
      const screen = worldToScreen(entity.render)
      const dimensions = typeof dimensionsForEntity === "function"
        ? dimensionsForEntity(entity)
        : {width: dimensionsForEntity * 2, height: dimensionsForEntity * 2}
      const halfWidth = Math.max(1, Number(dimensions?.width) || 0) / 2
      const halfHeight = Math.max(1, Number(dimensions?.height) || 0) / 2
      const deltaX = point.x - screen.x
      const deltaY = point.y - screen.y

      return {
        entity,
        inside: Math.abs(deltaX) <= halfWidth && Math.abs(deltaY) <= halfHeight,
        distance: deltaX * deltaX + deltaY * deltaY,
      }
    })
    .filter(candidate => candidate.inside)
    .sort((left, right) => left.distance - right.distance)[0]?.entity || null
}

export const applyAuthoritativeDamage = (entity, targetState) => {
  if (!entity || entityKey(entity.id) !== entityKey(targetState?.id)) return false

  entity.hull = Math.max(0, Number(targetState.hull) || 0)
  entity.maxHull = Math.max(0, Number(targetState.max_hull) || 0)
  entity.shields = Math.max(0, Number(targetState.shields) || 0)
  entity.maxShields = Math.max(0, Number(targetState.max_shields) || 0)
  entity.status = targetState.status
  return true
}
