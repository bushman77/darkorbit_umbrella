import test from "node:test"
import assert from "node:assert/strict"
import {mkdtemp, mkdir, readFile, rm, writeFile} from "node:fs/promises"
import {tmpdir} from "node:os"
import path from "node:path"
import {stageClient, localizeGameImports} from "../scripts/stage-client.mjs"

test("game source module imports use bundled Three.js, not a CDN", () => {
  assert.equal(localizeGameImports('import * as THREE from "three"'),
    'import * as THREE from "/game/vendor/three.module.js"')
  assert.equal(localizeGameImports("import {foo} from './foo.mjs'"),
    "import {foo} from './foo.mjs'")
})

test("desktop packaging stages renderer and assets without build-time network access", async () => {
  const temp = await mkdtemp(path.join(tmpdir(), "space-nova-stage-"))
  const client = path.join(temp, "clients/tauri")
  const game = path.join(temp, "apps/darkorbit_web/assets/js/game")
  const vendor = path.join(temp, "apps/darkorbit_web/assets/node_modules/three/build")
  const images = path.join(temp, "apps/darkorbit_web/priv/static/images/game/ships")
  try {
    for (const dir of [path.join(client, "ui"), game, vendor, images]) {
      await mkdir(dir, {recursive: true})
    }
    await writeFile(path.join(client, "ui/index.html"), "launcher")
    await writeFile(path.join(game, "stereo_view.js"), 'import * as THREE from "three"')
    await writeFile(path.join(game, "stereo_view_test.mjs"), "must not ship")
    await writeFile(path.join(vendor, "three.module.js"), "export {}")
    await writeFile(path.join(vendor, "three.core.js"), "export {}")
    await writeFile(path.join(images, "local-scout.svg"), "<svg></svg>")
    const destination = path.join(client, "dist/ui")
    const result = await stageClient({sourceRoot: temp, client, destination, includeNativeGame: false})
    assert.equal(result.modules, 1)
    assert.equal(await readFile(path.join(destination, "index.html"), "utf8"), "launcher")
    assert.match(await readFile(path.join(destination, "game/stereo_view.js"), "utf8"),
      /game\/vendor\/three.module.js/)
    assert.equal(await readFile(path.join(destination, "images/game/ships/local-scout.svg"), "utf8"),
      "<svg></svg>")
    await assert.rejects(readFile(path.join(destination, "game/stereo_view_test.mjs")))
  } finally {
    await rm(temp, {recursive: true, force: true})
  }
})

test("local render check never requires server-issued tokens or network connections", async () => {
  const source = await readFile(new URL("../ui/preview.mjs", import.meta.url), "utf8")
  const html = await readFile(new URL("../ui/preview.html", import.meta.url), "utf8")
  assert.match(source, /StereoSpaceView/)
  assert.match(source, /drawSolarAtlas/)
  assert.doesNotMatch(source, /\bWebSocket\b|\bfetch\s*\(|\bnew Socket\b/)
  assert.match(html, /NO SERVER REQUIRED/)
})
