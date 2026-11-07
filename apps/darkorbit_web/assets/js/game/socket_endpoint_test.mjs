import test from "node:test"
import assert from "node:assert/strict"
import {gameSocketEndpoint} from "./socket_endpoint.mjs"

test("hosted browser game uses same-origin channel endpoint", () => {
  assert.equal(gameSocketEndpoint(undefined), "/socket")
})

test("native client maps HTTPS to secure remote WebSocket", () => {
  assert.equal(gameSocketEndpoint("https://spacenova.ddns.net"),
    "wss://spacenova.ddns.net/socket")
  assert.equal(gameSocketEndpoint("https://spacenova.ddns.net:4000"),
    "wss://spacenova.ddns.net:4000/socket")
})

test("localhost development maps HTTP to ws", () => {
  assert.equal(gameSocketEndpoint("http://127.0.0.1:4000"),
    "ws://127.0.0.1:4000/socket")
  assert.throws(() => gameSocketEndpoint("file:///tmp/"))
})
