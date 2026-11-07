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
