// A previously registered helmet uses its persistent credential even when
// launched through an old or re-scanned QR invitation.
export function helmetSocketParams({pairCode, credential}) {
  if (credential) return {helmet_token: credential}
  if (pairCode) return {pair_code: pairCode}
  return {}
}
