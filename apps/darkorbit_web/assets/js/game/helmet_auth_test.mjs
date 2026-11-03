import test from "node:test"
import assert from "node:assert/strict"
import {helmetSocketParams} from "./helmet_auth.mjs"

test("registered phone uses only its persistent HMD credential", () => {
  assert.deepEqual(helmetSocketParams({credential: "remembered-token"}),
    {helmet_token: "remembered-token"})
})

test("QR invitation cannot be used to authenticate the viewer socket", () => {
  assert.deepEqual(helmetSocketParams({pairCode: "single-use-qr", credential: null}), {})
})

test("missing or empty credential provides no authority", () => {
  assert.deepEqual(helmetSocketParams({credential: null}), {})
  assert.deepEqual(helmetSocketParams({credential: ""}), {})
})
