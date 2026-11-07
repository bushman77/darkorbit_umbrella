// The native renderer is local; only Phoenix Channels use the remote host.
export function gameSocketEndpoint(origin) {
  if (!origin) return "/socket"
  const url = new URL("/socket", origin)
  if (url.protocol === "https:") url.protocol = "wss:"
  else if (url.protocol === "http:") url.protocol = "ws:"
  else throw Error("Game server must use HTTPS or localhost HTTP.")
  return url.href
}
