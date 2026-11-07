// Stored calibration is authoritative once present. Local phone settings are
// used to seed a newly migrated device, or to recover an unsynced edit.
// Never overwrite an unsynced local adjustment with an older database row.
export function restoredHelmetCalibration({server, local, dirty = false}) {
  const valid = source =>
    source && Number.isInteger(source.eyeGapPx) &&
    source.eyeGapPx >= -160 && source.eyeGapPx <= 80 &&
    Number.isInteger(source.eyeSepMm) &&
    source.eyeSepMm >= 40 && source.eyeSepMm <= 85

  const localValid = valid(local) ? local : {eyeGapPx: 8, eyeSepMm: 64}
  const serverValid = valid(server) ? server : null

  if (dirty || !serverValid) {
    return {calibration: localValid, needsSave: true}
  }

  return {calibration: serverValid, needsSave: false}
}
