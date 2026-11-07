// Settings are deliberately local-only. Native Tauri validates the origin,
// writes a non-secret settings file, and applies the proxy on the next launch.
const panel = document.querySelector("#networking-panel")
const open = document.querySelector("#networking-open")
const close = document.querySelector("#networking-close")
const form = document.querySelector("#networking-form")
const mode = document.querySelector("#proxy-mode")
const host = document.querySelector("#proxy-host")
const port = document.querySelector("#proxy-port")
const fields = document.querySelector("#proxy-fields")
const status = document.querySelector("#networking-status")
const override = document.querySelector("#networking-override")

const nativeInvoke = () => window.__TAURI__?.core?.invoke

function message(value, isError = false) {
  status.textContent = value
  status.dataset.error = String(isError)
}

function updateFields() {
  fields.hidden = mode.value !== "socks5"
}

async function refresh() {
  const invoke = nativeInvoke()
  if (!invoke) {
    message("The installed Tauri client is required to change native proxy settings.", true)
    form.querySelector('[type="submit"]').disabled = true
    return
  }
  try {
    const settings = await invoke("get_network_settings")
    mode.value = settings.saved.mode
    host.value = settings.saved.host
    port.value = String(settings.saved.port)
    override.hidden = !settings.forced_ssh_tunnel
    updateFields()
    message("Settings are stored on this computer and applied at startup.")
  } catch (cause) {
    message(String(cause), true)
  }
}

open?.addEventListener("click", () => {
  panel.hidden = false
  refresh()
})
close?.addEventListener("click", () => { panel.hidden = true })
mode?.addEventListener("change", updateFields)

form?.addEventListener("submit", async event => {
  event.preventDefault()
  const invoke = nativeInvoke()
  if (!invoke) return
  const settings = {
    mode: mode.value,
    host: host.value.trim(),
    port: Number(port.value),
  }
  if (!Number.isInteger(settings.port) || settings.port < 1 || settings.port > 65535) {
    message("Enter a valid TCP port (1–65535).", true)
    return
  }
  try {
    await invoke("save_network_settings", {settings})
    message("Saved. Restarting Space Nova to apply your connection preferences…")
    await invoke("restart_client")
  } catch (cause) {
    message("Unable to save networking settings: " + String(cause), true)
  }
})
