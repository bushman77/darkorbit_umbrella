import test from "node:test"
import assert from "node:assert/strict"
import {chooseHelmetOrigin} from "./helmet_network.mjs"

test("localhost pairing URLs use the laptop LAN address, retaining port", () => {
  assert.equal(chooseHelmetOrigin("http://localhost:4000", ["192.168.1.56", "10.0.0.5"]),
    "http://192.168.1.56:4000")
  assert.equal(chooseHelmetOrigin("http://127.0.0.1:4000", ["10.0.0.5"]),
    "http://10.0.0.5:4000")
})

test("network-resolvable URLs remain unchanged", () => {
  assert.equal(chooseHelmetOrigin("https://game.example.net", ["192.168.1.56"]),
    "https://game.example.net")
  assert.equal(chooseHelmetOrigin("http://192.168.0.7:4000", ["192.168.1.56"]),
    "http://192.168.0.7:4000")
})

test("do not create a misleading localhost QR code without an LAN address", () => {
  assert.equal(chooseHelmetOrigin("http://localhost:4000", []), "")
  assert.equal(chooseHelmetOrigin("http://localhost:4000", ["127.0.0.1"]), "")
  assert.equal(chooseHelmetOrigin("http://localhost:4000", ["http://evil.site/path"]), "")
})
