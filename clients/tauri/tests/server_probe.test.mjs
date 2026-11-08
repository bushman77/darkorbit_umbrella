import test from "node:test"
import assert from "node:assert/strict"
import {probeNativeServer} from "../ui/server_probe.mjs"

test("probe sends JSON without credentials to the selected server", async () => {
  let calls = 0
  const result = await probeNativeServer("http://127.0.0.1:4000", async (url, options) => {
    calls++
    assert.equal(url, "http://127.0.0.1:4000/api/native/probe")
    assert.equal(options.method, "POST")
    assert.equal(options.mode, "cors")
    assert.equal(options.credentials, "omit")
    assert.equal(options.body, "{}")
    assert.deepEqual(options.headers, {"content-type": "application/json"})
    return {ok: true, status: 200, json: async () => ({status: "ok"})}
  })
  assert.equal(calls, 1)
  assert.equal(result.ok, true)
})

test("probe distinguishes an undeployed backend from native transport failures", async () => {
  const missing = await probeNativeServer("http://127.0.0.1:4000",
    async () => ({ok: false, status: 404}))
  assert.equal(missing.ok, false)
  assert.match(missing.message, /404/)

  const failed = await probeNativeServer("http://127.0.0.1:4000", async () => {
    throw new TypeError("Load failed")
  })
  assert.equal(failed.ok, false)
  assert.match(failed.message, /Load failed/)
  assert.match(failed.message, /127\.0\.0\.1:4000/)
})

test("probe does not permit HTTP to non-loopback hosts", async () => {
  await assert.rejects(
    probeNativeServer("http://192.168.1.22:4000", async () => {
      throw Error("Should never fetch")
    }),
    /HTTPS/
  )
})
