import {serverOrigin} from "./server_url.mjs"

// Probe is intentionally unauthenticated and contains no pilot information.
// POST with JSON exercises the CORS preflight as well as the Phoenix API route.
export async function probeNativeServer(rawOrigin, request = fetch) {
  const origin = serverOrigin(rawOrigin)
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), 8000)
  try {
    const response = await request(origin + "/api/native/probe", {
      method: "POST",
      mode: "cors",
      credentials: "omit",
      cache: "no-store",
      headers: {"content-type": "application/json"},
      body: "{}",
      signal: controller.signal,
    })
    if (response.status === 404) {
      return {ok: false, message: "HTTP 404 from " + origin +
        ": this server does not have the native probe endpoint. Update the Phoenix backend."}
    }
    if (!response.ok) {
      return {ok: false, message: "Native probe returned HTTP " + response.status +
        " from " + origin + ". Check CORS, server logs and proxy settings."}
    }
    const payload = await response.json()
    if (payload.status !== "ok") {
      return {ok: false, message: "Unexpected native probe response from " + origin + "."}
    }
    return {ok: true, message: "Native JSON API reachable at " + origin +
      " — cross-origin POST completed successfully. You can now test pilot login."}
  } catch (error) {
    const reason = error?.name === "AbortError" ? "Request timed out" :
      (error?.message || "Unknown webview network error")
    return {ok: false, message: "Native webview cannot reach " + origin + ": " +
      reason + ". Check Network settings (disable SOCKS5 for local testing), " +
      "and select http://127.0.0.1:4000 for IPv4-only Phoenix."}
  } finally {
    clearTimeout(timeout)
  }
}
