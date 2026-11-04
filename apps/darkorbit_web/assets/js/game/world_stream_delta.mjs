// Join/resync supplies a complete map; ticks supply sparse deltas.
// Transient movement previews never affect the authoritative tick baseline.
export class WorldStreamDelta {
  constructor(map) { this.reset(map) }

  reset(map) {
    if (!map || !Number.isInteger(map.tick) || !Array.isArray(map.entities)) {
      throw new Error("Invalid world snapshot")
    }
    this.map = {...map}
    this.entities = new Map(map.entities.map(entity => [String(entity.id), entity]))
    return this.map
  }

  apply(delta) {
    if (!delta || !Number.isInteger(delta.tick) ||
        delta.base_tick !== this.map.tick || delta.tick <= delta.base_tick ||
        !Array.isArray(delta.entities) || !Array.isArray(delta.removed) ||
        !delta.changes || typeof delta.changes !== "object" ||
        Array.isArray(delta.changes)) return null

    const next = new Map(this.entities)
    for (const id of delta.removed) next.delete(String(id))
    for (const patch of delta.entities) {
      if (!patch || patch.id == null) return null
      const id = String(patch.id)
      const previous = next.get(id)
      if (!previous && !patch.kind) return null
      next.set(id, {...previous, ...patch})
    }

    const map = {...this.map, ...delta.changes, tick: delta.tick, entities: [...next.values()]}
    this.entities = next
    this.map = map
    return map
  }

  previewEntity(patch) {
    if (!patch || patch.id == null) return null
    const entity = this.entities.get(String(patch.id))
    return entity ? {...entity, ...patch} : null
  }
}
