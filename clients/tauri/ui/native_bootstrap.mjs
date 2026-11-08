// The game runs from packaged local assets. Only signed credentials,
// world-state and pilot commands cross the network; no remote HTML is loaded.
import {DEFAULT_SERVER_URL, serverOrigin} from "./server_url.mjs"
import {nativePostJson, nativeErrorMessage} from "./native_transport.mjs"

const login = document.querySelector("#native-login")
const form = document.querySelector("#native-login-form")
const error = document.querySelector("#native-login-error")
const busy = document.querySelector("#native-login-submit")
const game = document.querySelector("#game-client")
const status = document.querySelector("#native-session-status")
const server = document.querySelector("#native-server-name")
const authStorageKey = "space-nova-native-server"
const fallbackStorageKey = "sbs-space-server-origin"
let token = null
let origin = DEFAULT_SERVER_URL
let refreshTimer = null

try {
  origin = serverOrigin(localStorage.getItem(fallbackStorageKey) ||
    sessionStorage.getItem(authStorageKey) || DEFAULT_SERVER_URL)
} catch {
  origin = DEFAULT_SERVER_URL
}
server.textContent = origin

async function postJson(route, payload, bearer = null) {
  const response = await nativePostJson(origin, route, payload, bearer)
  const body = response.status === 204 ? {} : await response.json()
  if (!response.ok) throw Error(body.error || "Server refused this request (" + response.status + ").")
  return body
}

function showError(message) {
  error.textContent = message
  error.hidden = false
}

function resetToLogin(message) {
  token = null
  game.hidden = true
  login.hidden = false
  if (refreshTimer) clearInterval(refreshTimer)
  if (message) showError(message)
}

async function refreshToken() {
  if (!token) return
  try {
    const refreshed = await postJson("/api/native/refresh", {}, token)
    token = refreshed.token
    game.dataset.socketToken = refreshed.token
    status.textContent = "Secure pilot session active"
  } catch (_failure) {
    resetToLogin("Your pilot authorization expired. Sign in to reconnect.")
    // A fresh page is required to stop the existing world socket and HMD.
    window.location.replace("./game.html")
  }
}

form.addEventListener("submit", async event => {
  event.preventDefault()
  error.hidden = true
  busy.disabled = true
  busy.textContent = "Establishing secure link…"
  const username = document.querySelector("#native-username").value.trim()
  const password = document.querySelector("#native-password").value
  try {
    const session = await postJson("/api/native/login", {username, password})
    token = session.token
    document.querySelector("#native-password").value = ""
    game.dataset.socketToken = session.token
    game.dataset.layoutPlayerId = String(session.pilot_id)
    game.dataset.serverOrigin = origin
    window.SPACE_NOVA_SERVER_ORIGIN = origin
    login.hidden = true
    game.hidden = false
    status.textContent = "Secure pilot session active"
    await import("./native_game.js")
    refreshTimer = setInterval(refreshToken, 10 * 60 * 1000)
  } catch (cause) {
    resetToLogin(cause?.name === "AbortError"
      ? "Connection timed out. Check your SOCKS5 proxy and try again."
      : nativeErrorMessage(cause))
  } finally {
    busy.disabled = false
    busy.textContent = "Sign in and launch"
  }
})

// Intercept server-rendered form/navigation markup reused by the local build.
document.querySelector("#pilot-logout-form").addEventListener("submit", async event => {
  event.preventDefault()
  const oldToken = token
  token = null
  if (refreshTimer) clearInterval(refreshTimer)
  try {
    if (oldToken) await postJson("/api/native/logout", {}, oldToken)
  } catch (cause) {
    console.warn("Space Nova logout could not notify the server:", cause)
  } finally {
    window.location.replace("./index.html")
  }
})

for (const equipment of document.querySelectorAll("[data-native-equipment]")) {
  equipment.addEventListener("click", event => {
    event.preventDefault()
    status.textContent = "Equipment management is still on the Phoenix website; native loadouts are next."
  })
}
