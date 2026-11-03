import test from "node:test"
import assert from "node:assert/strict"
import {helmetSocketParams} from "./helmet_auth.mjs"

test("remembered credential takes precedence over one-time QR code", () => {
  assert.deepEqual(helmetSocketParams({pairCode: "spent-code", credential: "remembered-token"}),
    {helmet_token: "remembered-token"})
})

test("first-time scans send the pairing code, not a pilot token", () => {
  assert.deepEqual(helmetSocketParams({pairCode: "new-code", credential: null}),
    {pair_code: "new-code"})
})

test("an unpaired phone sends no authority", () => {
  assert.deepEqual(helmetSocketParams({pairCode: null, credential: null}), {})
})
