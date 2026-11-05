import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const readText = path => readFileSync(new URL(path, import.meta.url), "utf8")
const config = JSON.parse(readText("../src-tauri/tauri.conf.json"))
const signedBuildConfig = JSON.parse(readText("../src-tauri/tauri.updater.conf.json"))
const windowsConfig = JSON.parse(readText("../src-tauri/tauri.windows.conf.json"))
const packageConfig = JSON.parse(readText("../package.json"))
const rustSource = readText("../src-tauri/src/main.rs")
const cargoSource = readText("../src-tauri/Cargo.toml")

test("desktop version and updater verification settings are consistent", () => {
  assert.match(config.version, /^\d+\.\d+\.\d+$/)
  assert.equal(packageConfig.version, config.version)
  const cargoVersion = cargoSource.match(/^version = "([^"]+)"$/m)?.[1]
  assert.equal(cargoVersion, config.version)
  assert.equal(config.identifier, "game.sbs.space")
  assert.match(config.plugins.updater.pubkey, /^[A-Za-z0-9+/=]+$/)
  assert.ok(config.plugins.updater.pubkey.length > 100)
  assert.deepEqual(config.plugins.updater.endpoints, [
    "https://github.com/bushman77/darkorbit_umbrella/releases/latest/download/latest.json"
  ])
  assert.equal(config.plugins.updater.windows.installMode, "basicUi")
})

test("updater artifacts require an explicit signed publishing build", () => {
  assert.equal(config.bundle.createUpdaterArtifacts, undefined)
  assert.equal(signedBuildConfig.bundle.createUpdaterArtifacts, true)
  assert.deepEqual(config.app.security.capabilities, [])
  assert.deepEqual(windowsConfig.bundle.targets, ["nsis"])
})

test("native updater requires consent and never exposes installation commands to web pages", () => {
  assert.match(rustSource, /tauri_plugin_updater::UpdaterExt/)
  assert.match(rustSource, /MessageDialogButtons::OkCancel/)
  assert.match(rustSource, /if !accepted/)
  assert.match(rustSource, /update\.download_and_install/)
  assert.match(rustSource, /APPIMAGE/)
  assert.doesNotMatch(rustSource, /invoke_handler/)
})
