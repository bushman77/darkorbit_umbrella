// Build-time staging only: package renderer/source and visual assets from the
// same Git revision as this desktop client. No network requests at runtime.
import {cp, mkdir, readdir, readFile, rm, writeFile} from "node:fs/promises"
import {fileURLToPath} from "node:url"
import path from "node:path"
import {convertGameMarkup, nativeGameDocument} from "./native-game-markup.mjs"

export const clientRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
export const repoRoot = path.resolve(clientRoot, "../..")
export const outputRoot = path.join(clientRoot, "dist", "ui")
const moduleExtensions = new Set([".js", ".mjs"])
const localThreeImport = '"/game/vendor/three.module.js"'
const localGltfImport = '"/game/vendor/loaders/GLTFLoader.js"'
const threeFiles = [
  ["build/three.module.js", "three.module.js"],
  ["build/three.core.js", "three.core.js"],
  ["examples/jsm/loaders/GLTFLoader.js", "loaders/GLTFLoader.js"],
  ["examples/jsm/utils/BufferGeometryUtils.js", "utils/BufferGeometryUtils.js"],
  ["examples/jsm/utils/SkeletonUtils.js", "utils/SkeletonUtils.js"],
]

export function localizeGameImports(source) {
  // Avoid changing strings or user-generated content elsewhere in game files:
  // only quoted ES module specifiers in import/from statements are touched.
  return source.replace(
    /(\bfrom\s*|\bimport\s*)["']three\/addons\/loaders\/GLTFLoader\.js["']/g,
    (_match, prefix) => prefix + localGltfImport,
  ).replace(
    /(\bfrom\s*|\bimport\s*)["']three["']/g,
    (_match, prefix) => prefix + localThreeImport,
  )
}

export async function stageClient({
  sourceRoot = repoRoot,
  client = clientRoot,
  destination = outputRoot,
  includeNativeGame = true,
} = {}) {
  const uiSource = path.join(client, "ui")
  const gameSource = path.join(sourceRoot, "apps/darkorbit_web/assets/js/game")
  const gameImages = path.join(sourceRoot, "apps/darkorbit_web/priv/static/images/game")
  const threeSource = path.join(sourceRoot, "apps/darkorbit_web/assets/node_modules/three")
  const vendor = path.join(destination, "game", "vendor")

  // Refuse to stage a partial runtime. Installing the web assets' locked npm
  // dependencies is an explicit build prerequisite (and a CI step).
  for (const [sourcePath] of threeFiles) {
    try {
      await readFile(path.join(threeSource, sourcePath))
    } catch {
      throw new Error(
        "Three.js vendor files are missing. Run: npm ci --prefix apps/darkorbit_web/assets",
      )
    }
  }

  await rm(destination, {recursive: true, force: true})
  await mkdir(destination, {recursive: true})
  for (const entry of await readdir(uiSource, {withFileTypes: true})) {
    if (entry.isFile()) {
      await cp(path.join(uiSource, entry.name), path.join(destination, entry.name))
    }
  }

  const gameDestination = path.join(destination, "game")
  await mkdir(gameDestination, {recursive: true})
  let modules = 0
  for (const name of await readdir(gameSource)) {
    if (!moduleExtensions.has(path.extname(name)) || name.endsWith("_test.mjs")) continue
    const source = await readFile(path.join(gameSource, name), "utf8")
    await writeFile(path.join(gameDestination, name), localizeGameImports(source))
    modules += 1
  }

  await mkdir(vendor, {recursive: true})
  for (const [sourcePath, destinationPath] of threeFiles) {
    const target = path.join(vendor, destinationPath)
    await mkdir(path.dirname(target), {recursive: true})
    const source = await readFile(path.join(threeSource, sourcePath), "utf8")
    // Addon sources import the same Three.js instance as the main renderer.
    await writeFile(target, localizeGameImports(source))
  }
  await mkdir(path.join(destination, "images"), {recursive: true})
  await cp(gameImages, path.join(destination, "images", "game"), {recursive: true})

  if (includeNativeGame) {
    const publicAssets = path.join(sourceRoot, "apps/darkorbit_web/priv/static/assets")
    const compiled = [
      ["native_game.js", "native_game.js"],
      ["css/app.css", "native_game.css"],
    ]
    for (const [from, to] of compiled) {
      try {
        await cp(path.join(publicAssets, from), path.join(destination, to))
      } catch (cause) {
        throw new Error("Native game assets are missing (" + from +
          "). Run: node clients/tauri/scripts/build-native-assets.mjs", {cause})
      }
    }
    const template = await readFile(path.join(sourceRoot,
      "apps/darkorbit_web/lib/darkorbit_web/controllers/game_html/show.html.heex"), "utf8")
    const gameHtml = nativeGameDocument(convertGameMarkup(template))
    await writeFile(path.join(destination, "game.html"), gameHtml)
  }

  return {destination, modules}
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  stageClient().then(
    ({destination, modules}) =>
      console.log("Space Nova: staged " + modules + " game modules and graphics in " + destination),
    error => { console.error(error); process.exitCode = 1 },
  )
}
