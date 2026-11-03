// QR invitations are redeemed over HTTP and stored before this function
// is used. WebSocket authentication is restricted to persistent helmet tokens.
export function helmetSocketParams({credential}) {
  if (typeof credential === "string" && credential.length > 0) {
    return {helmet_token: credential}
  }
  return {}
}
