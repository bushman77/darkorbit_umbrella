import {serverOrigin} from "./server_url.mjs"
import {nativePostJson, nativeErrorMessage} from "./native_transport.mjs"

// Probe is intentionally unauthenticated and contains no pilot information.
// POST with JSON exercises the CORS preflight as well as the Phoenix API route.
export async function probeNativeServer(rawOrigin, request = fetch,
  invoke = globalThis.__TAURI__?.core?.invoke) {
  const origin = serverOrigin(rawOrigin)
  try {
    const response = await nativePostJson(origin, "/api/native/probe", {}, null,
      {request, invoke, timeoutMs: 8000})
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
    return {ok: true, message: (response.nativeBridge
      ? "Native loopback bridge reached Phoenix successfully at "
      : "Native webview JSON API reachable at ") + origin +
      ". You can now test pilot login."}
  } catch (error) {
    const reason = nativeErrorMessage(error)
    return {ok: false, message: "Native client cannot reach " + origin + ": " +
      reason + ". Check Network settings (disable SOCKS5 for local testing), " +
      "and select http://127.0.0.1:4000 for IPv4-only Phoenix."}
  }
}
