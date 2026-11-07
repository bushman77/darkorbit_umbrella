// Build local assets from exactly the checked-out Phoenix source revision.
// This runs when creating the native Tauri installer or launching dev mode.
// It never downloads game code from the production EC2 server.
import {spawnSync} from "node:child_process"
import {repoRoot} from "./stage-client.mjs"

const tasks = [
  ["deps.get"],
  ["esbuild", "darkorbit_native"],
  ["tailwind", "darkorbit_web"],
]

for (const args of tasks) {
  console.log("Space Nova native assets: mix " + args.join(" "))
  const result = spawnSync("mix", args, {
    cwd: repoRoot,
    stdio: "inherit",
    env: {...process.env, MIX_ENV: "dev"},
  })
  if (result.error) {
    console.error("Cannot invoke mix. Install Elixir and Erlang/OTP before building the native client.")
    console.error(result.error.message)
    process.exit(1)
  }
  if (result.status !== 0) process.exit(result.status || 1)
}
