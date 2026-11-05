import test from "node:test"
import assert from "node:assert/strict"
import {
  DEFAULT_SERVER_URL, LOCAL_SERVER_URL, serverOrigin,
  gameUrl, registrationUrl, homeUrl, destinationUrl, initialServerOrigin
} from "../ui/server_url.mjs"

test("default launches the live Space Nova server", () => {
  assert.equal(DEFAULT_SERVER_URL, "https://spacenova.ddns.net:4000")
  assert.equal(gameUrl(DEFAULT_SERVER_URL), "https://spacenova.ddns.net:4000/play")
  assert.equal(registrationUrl(DEFAULT_SERVER_URL), "https://spacenova.ddns.net:4000/register")
  assert.equal(homeUrl(DEFAULT_SERVER_URL), "https://spacenova.ddns.net:4000/")
})

test("the local development server supports registration and gameplay", () => {
  assert.equal(LOCAL_SERVER_URL, "http://127.0.0.1:4000")
  assert.equal(gameUrl(LOCAL_SERVER_URL), "http://127.0.0.1:4000/play")
  assert.equal(registrationUrl(LOCAL_SERVER_URL), "http://127.0.0.1:4000/register")
  assert.equal(homeUrl("http://localhost:4000/"), "http://localhost:4000/")
  assert.equal(gameUrl("http://[::1]:4000"), "http://[::1]:4000/play")
})

test("remote game servers require HTTPS", () => {
  assert.equal(gameUrl("https://game.example.org:4000"), "https://game.example.org:4000/play")
  assert.throws(() => gameUrl("http://game.example.org:4000"), /HTTPS/)
  assert.throws(() => registrationUrl("http://192.168.1.5:4000"), /HTTPS/)
})

test("rejects schemes, embedded credentials and arbitrary routes", () => {
  for (const value of [
    "", "https://user:pass@game.example.org", "https://game.example.org:4000/equipment",
    "https://game.example.org:4000/?token=abc", "https://game.example.org:4000/#fragment",
    "javascript:alert(1)", "file:///etc/passwd", "not a url"
  ]) {
    assert.throws(() => serverOrigin(value), value)
  }
  for (const route of ["/verify-account", "/logout", "//other.example.org", "/equipment"]) {
    assert.throws(() => destinationUrl(DEFAULT_SERVER_URL, route), /Unsupported/)
  }
})

test("migrates launcher origins saved by older builds", () => {
  assert.equal(initialServerOrigin(null), DEFAULT_SERVER_URL)
  assert.equal(initialServerOrigin("https://spacenova.ddns.net"), DEFAULT_SERVER_URL)
  assert.equal(initialServerOrigin("http://127.0.0.1"), LOCAL_SERVER_URL)
  assert.equal(initialServerOrigin("http://localhost"), "http://localhost:4000")
  assert.equal(initialServerOrigin("https://example.org:4000"), "https://example.org:4000")
})

test("requires explicit port 4000", () => {
  for (const origin of [
    "http://127.0.0.1", "http://localhost:80", "https://spacenova.ddns.net",
    "https://spacenova.ddns.net:443", "https://game.example.org:4500"
  ]) assert.throws(() => gameUrl(origin), /port 4000/, origin)
})

test("canonicalizes whitespace and hostname", () => {
  assert.equal(serverOrigin("  HTTPS://GAME.EXAMPLE.ORG:4000/  "), "https://game.example.org:4000")
})
