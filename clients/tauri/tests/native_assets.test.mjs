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
  assert.equal(localizeGameImports(
    'import {GLTFLoader} from "three/addons/loaders/GLTFLoader.js"'),
    'import {GLTFLoader} from "/game/vendor/loaders/GLTFLoader.js"')
})

test("desktop packaging stages renderer and assets without build-time network access", async () => {
  const temp = await mkdtemp(path.join(tmpdir(), "space-nova-stage-"))
  const client = path.join(temp, "clients/tauri")
  const game = path.join(temp, "apps/darkorbit_web/assets/js/game")
  const vendor = path.join(temp, "apps/darkorbit_web/assets/node_modules/three")
  const images = path.join(temp, "apps/darkorbit_web/priv/static/images/game/ships")
  const station = path.join(temp, "apps/darkorbit_web/priv/static/images/game/station")
  try {
    for (const dir of [path.join(client, "ui"), game,
      path.join(vendor, "build"), path.join(vendor, "examples/jsm/loaders"),
      path.join(vendor, "examples/jsm/utils"), images, station]) {
      await mkdir(dir, {recursive: true})
    }
    await writeFile(path.join(client, "ui/index.html"), "launcher")
    await writeFile(path.join(game, "stereo_view.js"), 'import * as THREE from "three"')
    await writeFile(path.join(game, "stereo_view_test.mjs"), "must not ship")
    await writeFile(path.join(vendor, "build/three.module.js"), "export {}")
    await writeFile(path.join(vendor, "build/three.core.js"), "export {}")
    await writeFile(path.join(vendor, "examples/jsm/loaders/GLTFLoader.js"),
      "import {Group} from 'three'; export class GLTFLoader {}")
    await writeFile(path.join(vendor, "examples/jsm/utils/BufferGeometryUtils.js"),
      "import {Group} from 'three'")
    await writeFile(path.join(vendor, "examples/jsm/utils/SkeletonUtils.js"),
      "import {Group} from 'three'")
    await writeFile(path.join(images, "local-scout.svg"), "<svg></svg>")
    await writeFile(path.join(station, "mara_venn.glb"), "local-blender-model")
    const destination = path.join(client, "dist/ui")
    const result = await stageClient({sourceRoot: temp, client, destination, includeNativeGame: false})
    assert.equal(result.modules, 1)
    assert.equal(await readFile(path.join(destination, "index.html"), "utf8"), "launcher")
    assert.match(await readFile(path.join(destination, "game/stereo_view.js"), "utf8"),
      /game\/vendor\/three.module.js/)
    assert.equal(await readFile(path.join(destination, "images/game/ships/local-scout.svg"), "utf8"),
      "<svg></svg>")
    assert.equal(await readFile(path.join(destination, "images/game/station/mara_venn.glb"), "utf8"),
      "local-blender-model", "desktop bundles the Blender GLB without a runtime download")
    assert.match(await readFile(path.join(destination, "game/vendor/loaders/GLTFLoader.js"), "utf8"),
      /vendor\/three\.module\.js/, "loader imports the same local Three.js instance")
    assert.match(await readFile(path.join(destination, "game/vendor/utils/SkeletonUtils.js"), "utf8"),
      /vendor\/three\.module\.js/)
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
