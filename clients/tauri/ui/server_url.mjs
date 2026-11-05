export const DEFAULT_SERVER_URL = "https://spacenova.ddns.net"
export const LOCAL_SERVER_URL = "http://127.0.0.1:4000"

const LOOPBACK_HOSTS = new Set(["127.0.0.1", "localhost", "[::1]"])
const LAUNCH_ROUTES = new Set(["/", "/play", "/register"])

// Only accept a server origin. Never carry arbitrary paths, credentials or
// query strings into an authenticated Phoenix browser session.
export function serverOrigin(raw) {
  if (typeof raw !== "string" || raw.trim() === "") {
    throw new Error("Enter a server address.")
  }

  let url
  try {
    url = new URL(raw.trim())
  } catch {
    throw new Error("Enter an absolute HTTP or HTTPS server address.")
  }

  if (!["http:", "https:"].includes(url.protocol)) {
    throw new Error("Only HTTP and HTTPS servers are supported.")
  }
  if (url.username || url.password) {
    throw new Error("Do not include credentials in the server address.")
  }
  if (url.pathname !== "/" || url.search || url.hash) {
    throw new Error("Enter only the server address, without a path, query or fragment.")
  }
  if (url.protocol === "http:" && !LOOPBACK_HOSTS.has(url.hostname)) {
    throw new Error("Remote multiplayer servers must use HTTPS.")
  }
  return url.origin
}

export function destinationUrl(raw, route) {
  if (!LAUNCH_ROUTES.has(route)) {
    throw new Error("Unsupported launcher destination.")
  }
  return new URL(route, serverOrigin(raw)).href
}

export function gameUrl(raw) {
  return destinationUrl(raw, "/play")
}

export function registrationUrl(raw) {
  return destinationUrl(raw, "/register")
}

export function homeUrl(raw) {
  return destinationUrl(raw, "/")
}
