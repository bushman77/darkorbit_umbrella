// Visual selection only. Neither an HMD nor a desktop client may request
// docking by declaring this state: MapServer owns docked_pilots.
export function greenStarbaseInteriorVisible({docked, mapId} = {}) {
  return docked === true && typeof mapId === "string" &&
    /^sol:free_[1-9][0-9]*$/.test(mapId)
}

// Map ID and berth state arrive together in the authenticated world snapshot.
export function pilotDockedInWorld(map, ownId) {
  return ownId != null && typeof map?.map_id === "string" &&
    /^sol:free_[1-9][0-9]*$/.test(map.map_id) &&
    Array.isArray(map.docked_pilots) &&
    map.docked_pilots.some(id => String(id) === String(ownId))
}
