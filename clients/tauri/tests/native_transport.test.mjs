import test from "node:test"
import assert from "node:assert/strict"
import {isLocalNativeServer, nativePostJson} from "../ui/native_transport.mjs"

test("native transport recognizes only loopback HTTP port 4000", () => {
  assert.equal(isLocalNativeServer("http://127.0.0.1:4000"), true)
  assert.equal(isLocalNativeServer("http://localhost:4000"), true)
  assert.equal(isLocalNativeServer("https://spacenova.ddns.net"), false)
  assert.throws(() => isLocalNativeServer("http://192.168.0.20:4000"), /HTTPS/)
})

test("native loopback login sends only the whitelisted route and credentials via IPC", async () => {
  let captured
  const result = await nativePostJson("http://127.0.0.1:4000", "/api/native/login",
    {username: "pilot", password: "test-password"}, null, {
      request: () => { throw Error("Webview fetch should not be called") },
      invoke: async (command, args) => {
        captured = {command, args}
        return {status: 200, body: '{"token":"test-token","pilot_id":7}'}
      },
    })
  assert.equal(result.ok, true)
  assert.equal(result.nativeBridge, true)
  assert.deepEqual(await result.json(), {token: "test-token", pilot_id: 7})
  assert.equal(captured.command, "native_loopback_post")
  assert.equal(captured.args.route, "/api/native/login")
  assert.deepEqual(captured.args.payload, {username: "pilot", password: "test-password"})
  assert.equal(captured.args.bearer, null)
})

test("native refresh and logout accept bearer token without persistence", async () => {
  for (const route of ["/api/native/refresh", "/api/native/logout"]) {
    const result = await nativePostJson("http://127.0.0.1:4000", route, {}, "test-token", {
      invoke: async (_command, args) => {
        assert.equal(args.bearer, "test-token")
        return {status: 204, body: ""}
      },
    })
    assert.equal(result.status, 204)
    assert.deepEqual(await result.json(), {})
  }
})

test("remote server continues to use HTTPS fetch, never IPC", async () => {
  const result = await nativePostJson("https://spacenova.ddns.net",
    "/api/native/probe", {}, null, {
      request: async (url, opts) => {
        assert.equal(url, "https://spacenova.ddns.net/api/native/probe")
        assert.equal(opts.credentials, "omit")
        return {ok: true, status: 200, json: async () => ({status: "ok"})}
      },
      invoke: async () => { throw Error("IPC must not handle remote server") },
    })
  assert.equal(result.ok, true)
})

test("route whitelist prevents arbitrary backend access", async () => {
  await assert.rejects(
    nativePostJson("http://127.0.0.1:4000", "/admin", {}, null, {
      invoke: () => { throw Error("IPC must not be called") },
    }),
    /Unsupported native JSON route/
  )
})
