import {
  DEFAULT_SERVER_URL, LOCAL_SERVER_URL, registrationUrl, homeUrl, serverOrigin,
  initialServerOrigin
} from "./server_url.mjs"

const input = document.querySelector("#server-url")
const form = document.querySelector("#connect-form")
const error = document.querySelector("#error")
const local = document.querySelector("#use-local")
const register = document.querySelector("#register-pilot")
const homepage = document.querySelector("#visit-home")
const preview = document.querySelector("#preview-local")
const storageKey = "sbs-space-server-origin"

try {
  input.value = initialServerOrigin(localStorage.getItem(storageKey))
} catch {
  input.value = DEFAULT_SERVER_URL
}

local.addEventListener("click", () => {
  input.value = LOCAL_SERVER_URL
  error.hidden = true
  input.focus()
})

function navigateTo(destinationFor) {
  error.hidden = true
  try {
    const origin = serverOrigin(input.value)
    const destination = destinationFor(origin)
    try {
      localStorage.setItem(storageKey, origin)
    } catch {
      // Private webview storage should not prevent a connection.
    }
    // Navigate the top-level webview, not an iframe: Phoenix cookies,
    // CSRF protection, LiveView and /socket keep their same-origin model.
    // The remote web page has no native Tauri capabilities.
    window.location.assign(destination)
  } catch (cause) {
    error.textContent = cause.message || "Unable to use that server address."
    error.hidden = false
  }
}

// The main game is installed locally. Only authentication and real-time
// authoritative commands use the selected remote Phoenix server.
form.addEventListener("submit", event => {
  event.preventDefault()
  error.hidden = true
  try {
    const origin = serverOrigin(input.value)
    sessionStorage.setItem("space-nova-native-server", origin)
    localStorage.setItem(storageKey, origin)
    window.location.assign("./game.html")
  } catch (cause) {
    error.textContent = cause.message || "Unable to select that game server."
    error.hidden = false
  }
})
register.addEventListener("click", () => navigateTo(registrationUrl))
homepage.addEventListener("click", () => navigateTo(homeUrl))

// Explicit offline smoke check; no remote navigation or pilot credentials.
preview.addEventListener("click", () => window.location.assign("./preview.html"))
