// Build-time staging only: package renderer/source and visual assets from the
// same Git revision as this desktop client. No network requests at runtime.
import {cp, mkdir, readdir, readFile, rm, writeFile} from "node:fs/promises"
import {fileURLToPath} from "node:url"
import path from "node:path"

export const clientRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
export const repoRoot = path.resolve(clientRoot, "../..")
export const outputRoot = path.join(clientRoot, "dist", "ui")
const moduleExtensions = new Set([".js", ".mjs"])
const localThreeImport = '"/game/vendor/three.module.js"'

export function localizeGameImports(source) {
  // Avoid changing strings or user-generated content elsewhere in game files:
  // only quoted ES module specifiers in import/from statements are touched.
  return source.replace(
    /(\bfrom\s*|\bimport\s*)["']three["']/g,
    (_match, prefix) => prefix + localThreeImport,
  )
}

export async function stageClient({
  sourceRoot = repoRoot,
  client = clientRoot,
  destination = outputRoot,
} = {}) {
  const uiSource = path.join(client, "ui")
  const gameSource = path.join(sourceRoot, "apps/darkorbit_web/assets/js/game")
  const gameImages = path.join(sourceRoot, "apps/darkorbit_web/priv/static/images/game")
  const threeSource = path.join(sourceRoot, "apps/darkorbit_web/assets/node_modules/three/build")
  const vendor = path.join(destination, "game", "vendor")

  // Refuse to stage a partial runtime. Installing the web assets' locked npm
  // dependencies is an explicit build prerequisite (and a CI step).
  for (const name of ["three.module.js", "three.core.js"]) {
    try {
      await readFile(path.join(threeSource, name))
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
  for (const name of ["three.module.js", "three.core.js"]) {
    await cp(path.join(threeSource, name), path.join(vendor, name))
  }
  await mkdir(path.join(destination, "images"), {recursive: true})
  await cp(gameImages, path.join(destination, "images", "game"), {recursive: true})

  return {destination, modules}
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  stageClient().then(
    ({destination, modules}) =>
      console.log("Space Nova: staged " + modules + " game modules and graphics in " + destination),
    error => { console.error(error); process.exitCode = 1 },
  )
}
