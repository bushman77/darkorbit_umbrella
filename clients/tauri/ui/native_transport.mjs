// JSON-only native bridge for local Phoenix on port 4000. Unlike the WebKit
// fetch path, the Rust command does not depend on custom-scheme CORS handling.
// Remote servers keep the ordinary HTTPS fetch transport.
import {serverOrigin} from "./server_url.mjs"

const ROUTES = new Set([
  "/api/native/probe", "/api/native/login",
  "/api/native/refresh", "/api/native/logout",
])

export function isLocalNativeServer(rawOrigin) {
  const origin = serverOrigin(rawOrigin)
  return origin === "http://127.0.0.1:4000" || origin === "http://localhost:4000"
}

// Returns a Response-like object; never stores credentials or bearer tokens.
export async function nativePostJson(rawOrigin, route, payload, bearer = null, {
  request = globalThis.fetch,
  invoke = globalThis.__TAURI__?.core?.invoke,
  timeoutMs = 16000,
} = {}) {
  const origin = serverOrigin(rawOrigin)
  if (!ROUTES.has(route)) throw Error("Unsupported native JSON route.")
  if (isLocalNativeServer(origin) && typeof invoke === "function") {
    const native = await invoke("native_loopback_post", {route, payload, bearer})
    const body = native.status === 204 ? {} : JSON.parse(native.body)
    return {
      ok: native.status >= 200 && native.status < 300,
      status: native.status,
      nativeBridge: true,
      json: async () => body,
    }
  }

  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), timeoutMs)
  try {
    return await request(origin + route, {
      method: "POST",
      mode: "cors",
      credentials: "omit",
      cache: "no-store",
      headers: {
        "content-type": "application/json",
        ...(bearer ? {"authorization": "Bearer " + bearer} : {}),
      },
      body: JSON.stringify(payload),
      signal: controller.signal,
    })
  } finally {
    clearTimeout(timeout)
  }
}
