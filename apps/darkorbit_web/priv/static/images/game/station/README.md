# Space Nova station character assets

Place the original Blender export at **mara_venn.glb** in this directory.

- Browser/static URL: `/images/game/station/mara_venn.glb`
- Tauri: `clients/tauri/scripts/stage-client.mjs` copies this directory into
  the standalone client's local asset bundle during `npm run dev` or build.
- The GLB is **presentation-only**. NPC identity, speech, room and position
  continue to come from `Core.World.StationAttendants` through MapServer.
- If the file is missing or cannot be loaded, the existing procedural repair
  attendant remains visible. Restart/reload the game after adding the GLB.

## Blender export guidance

Export only the character meshes, materials, and any required rig/parents.
Exclude Blender cameras, lights, reference images and helper geometry.
Export **GLB (glTF 2.0 binary)** with material textures embedded. Keep the model
upright, feet at ground level, and facing toward the repair kiosk visitors.
The runtime automatically rescales it to 8.5 station units and applies no
additional yaw for Mara's current Blender export. Avoid Draco/meshopt compression until
their decoders are bundled.

For the current mobile SBS experiment aim for <= 20k triangles, <= 5 MB GLB,
and modest texture sizes (ideally 1024px or less). These are initial targets,
not enforced limits. No textures, polygons or animations are sent over game
state sockets.

Once exported to this directory, optionally commit the GLB to `star_base`
so the same character ships with future Steam builds.
