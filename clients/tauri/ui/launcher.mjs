import { DEFAULT_SERVER_URL, gameUrl, serverOrigin } from "./server_url.mjs"

const input = document.querySelector("#server-url")
const form = document.querySelector("#connect-form")
const error = document.querySelector("#error")
const local = document.querySelector("#use-local")
const storageKey = "sbs-space-server-origin"

try {
  input.value = localStorage.getItem(storageKey) || DEFAULT_SERVER_URL
} catch {
  input.value = DEFAULT_SERVER_URL
}

local.addEventListener("click", () => {
  input.value = DEFAULT_SERVER_URL
  error.hidden = true
  input.focus()
})

form.addEventListener("submit", (event) => {
  event.preventDefault()
  error.hidden = true
  try {
    const origin = serverOrigin(input.value)
    const destination = gameUrl(origin)
    try {
      localStorage.setItem(storageKey, origin)
    } catch {
      // Private webview storage should not prevent a connection.
    }
    // Navigate the top-level webview, not an iframe: Phoenix cookies,
    // CSRF protection, LiveView and /socket keep their normal same-origin model.
    window.location.assign(destination)
  } catch (cause) {
    error.textContent = cause.message || "Unable to use that server address."
    error.hidden = false
  }
})
