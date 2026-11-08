// The phone cannot resolve the laptop's localhost. Keep the browser's
// scheme/port and substitute a server-discovered LAN address when necessary.
const loopback = new Set(["localhost", "127.0.0.1", "[::1]", "::1"])

export function chooseHelmetOrigin(pageOrigin, networkHosts = []) {
  let page
  try {
    page = new URL(pageOrigin)
  } catch (_error) {
    return ""
  }

  if (!loopback.has(page.hostname.toLowerCase())) return page.origin

  const candidate = networkHosts.find(host =>
    typeof host === "string" && /^[a-zA-Z0-9.-]+$/.test(host) &&
    !loopback.has(host.toLowerCase())
  )
  if (!candidate) return ""

  try {
    page.hostname = candidate
    return page.origin
  } catch (_error) {
    return ""
  }
}

/**
 * The standalone Tauri client uses localhost HTTP for world traffic, but the
 * Galaxy HMD requires HTTPS to access motion sensors. Prefer the explicit
 * server-advertised phone origin only if it matches an actual discovered LAN
 * interface; otherwise retain the existing documented HTTP pairing behavior.
 */
export function helmetPairingOrigin(pageOrigin, networkHosts = [], lanHttpsOrigin = null) {
  const fallback = chooseHelmetOrigin(pageOrigin, networkHosts)
  if (typeof lanHttpsOrigin !== "string" || !lanHttpsOrigin) return fallback
  try {
    const endpoint = new URL(lanHttpsOrigin)
    if (endpoint.protocol !== "https:" || endpoint.port !== "4443" ||
        endpoint.username || endpoint.password ||
        endpoint.pathname !== "/" || endpoint.search || endpoint.hash ||
        !networkHosts.includes(endpoint.hostname)) return fallback
    return endpoint.origin
  } catch (_error) {
    return fallback
  }
}
