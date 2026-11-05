import {findSolarBody} from "./solar_system.mjs"

// Space is only a schematic: a blank-map click targets the already selected
// celestial body, never a fabricated world-space coordinate.
export function solarMenuTarget(clickedId,selectedId) {
  if(findSolarBody(clickedId))return clickedId
  return findSolarBody(selectedId)?selectedId:null
}

export function canNavigateSolar(id,navigation,connected,pending) {
  return Boolean(findSolarBody(id)&&id!=="sun"&&connected&&!pending&&
    navigation?.system_id==="sol"&&navigation.status==="idle"&&
    navigation.location_id!==id)
}
