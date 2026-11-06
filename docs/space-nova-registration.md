
# Space Nova registration verification hardening

Implemented on the existing `sbs` branch, without changing the starter-ship
transaction or requiring a new migration (verification is an existing JSONB
field).

- Initial registration stores a SHA-256 digest of a 256-bit random
  URL-safe token in `player_accounts.verification.hash`.
- Tokens expire after **24 hours** and are single-use. Verification removes
  the digest and expiry; unverified sessions cannot log in.
- A GET from email displays the confirmation page without activating the
  account. A CSRF-protected POST confirms activation; link-preview scanners
  do not activate accounts simply by opening a URL.
- `GET/POST /register/resend` allows recovery from missing/expired emails.
  The endpoint returns the same generic result for unknown, verified,
  throttled, and eligible accounts, with a **60-second minimum interval**
  and at most **five resends per rolling 24 hours** per unverified account.
  The account row is locked when rotating the token.
- Initial outbound delivery can fail after the account and starter ship
  commit. The UI directs players to the resend form, which issues a fresh
  token and retries delivery. No player assets or identities are duplicated.
- Email delivery uses the configured Swoosh mailer. In production,
  `RESEND_API_KEY` and `REGISTRATION_FROM_EMAIL` remain mandatory before
  registration/resend becomes enabled. No credentials or actual outbound mail
  provider configuration are committed.
- Legacy unverified tokens created before the digest/expiry change have no
  expiration metadata and **must be replaced** through the resend flow.
  Existing verified accounts and their sessions remain unaffected.
- The new path is covered by domain and controller tests plus a GitHub Actions
  registration CI workflow.

## Remaining production readiness work

1. Confirm a verified sender identity and a functioning outbound email
   provider on EC2; register and verify a pilot with a real inbox.
2. Add per-IP/IP-prefix rate limits or bot-abuse controls to public
   registration and resend, in addition to the per-account resend controls.
3. Implement password reset, opt-in retention policy for abandoned accounts,
   and an operational email-outbox mechanism for durable retries. The current
   recovery is **user-initiated resend**, not automatic background delivery.
4. Decide whether email addresses, usernames and pilot callsigns must all
   be case-insensitively unique. New registration emails are normalized to
   lower-case; legacy mixed-case addresses are not automatically migrated.
5. Audit that public proxies and logs do not record query-string bearer tokens.
   The verification page sets no-store and no-referrer headers.

**Do not enable production registration simply by deploying this code.**
The EC2 release remains unchanged until explicitly rebuilt, deployed,
and configured with an approved mail provider.
