import test from "node:test"
import assert from "node:assert/strict"
import { DEFAULT_SERVER_URL, serverOrigin, gameUrl } from "../ui/server_url.mjs"

test("localhost launches authenticated Phoenix play route", () => {
  assert.equal(DEFAULT_SERVER_URL, "https://localhost:4001")
  assert.equal(gameUrl(DEFAULT_SERVER_URL), "https://localhost:4001/play")
  assert.equal(gameUrl("http://127.0.0.1:4000"), "http://127.0.0.1:4000/play")
  assert.equal(gameUrl("http://localhost:4000/"), "http://localhost:4000/play")
  assert.equal(gameUrl("http://[::1]:4000"), "http://[::1]:4000/play")
})

test("remote game servers require HTTPS", () => {
  assert.equal(gameUrl("https://game.example.org"), "https://game.example.org/play")
  assert.throws(() => gameUrl("http://game.example.org"), /HTTPS/)
  assert.throws(() => gameUrl("http://192.168.1.5:4000"), /HTTPS/)
})

test("rejects schemes, embedded credentials and arbitrary routes", () => {
  for (const value of [
    "", "https://user:pass@game.example.org", "https://game.example.org/equipment",
    "https://game.example.org/?token=abc", "https://game.example.org/#fragment",
    "javascript:alert(1)", "file:///etc/passwd", "not a url"
  ]) {
    assert.throws(() => serverOrigin(value), value)
  }
})

test("canonicalizes whitespace and hostname", () => {
  assert.equal(serverOrigin("  HTTPS://GAME.EXAMPLE.ORG/  "), "https://game.example.org")
})
