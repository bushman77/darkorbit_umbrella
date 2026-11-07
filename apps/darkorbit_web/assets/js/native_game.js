// Standalone Space Nova desktop gameplay entrypoint.
// Mix/esbuild packages Phoenix Channels, Three.js and all game modules locally.
// The launch page supplies a signed socket token after HTTPS authentication.
import {startGameClient} from "./game/client"

startGameClient()
