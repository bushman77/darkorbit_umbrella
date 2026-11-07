
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

## Outbound email platform (Swoosh + optional SMTP)

Space Nova uses Swoosh for all pilot verification emails. Development and
automated tests retain their existing Local and Test adapters. In production,
set one transport and verify it independently before opening registration.

### SMTP provider (port 587, STARTTLS)

Configure the private environment file used by the running EC2 systemd
service at /home/ubuntu/.config/space_mmo.env:

~~~dotenv
SPACE_NOVA_EMAIL_PROVIDER=smtp
SMTP_HOST=smtp.your-mail-provider.example
SMTP_PORT=587
SMTP_USERNAME=your-smtp-username
SMTP_PASSWORD=your-smtp-credential
REGISTRATION_FROM_EMAIL=pilots@your-verified-domain.example
SPACE_NOVA_REGISTRATION_OPEN=false
~~~

The SMTP transport requires a verified sender at your email provider.
The application performs SMTP authentication and requires TLS with CA
and hostname verification. Port 465 (implicit TLS) is also supported; port
2525 (STARTTLS) is supported for providers offering that alternative. Do
not use port 25, plaintext SMTP, or disable certificate verification.
The gen_smtp dependency is used by Swoosh's SMTP adapter.

### Existing Resend API option

Resend remains supported as the HTTP API transport:

~~~dotenv
SPACE_NOVA_EMAIL_PROVIDER=resend
RESEND_API_KEY=your-private-resend-api-key
REGISTRATION_FROM_EMAIL=pilots@your-verified-domain.example
SPACE_NOVA_REGISTRATION_OPEN=false
~~~

The provider defaults to Resend only if RESEND_API_KEY exists and
SPACE_NOVA_EMAIL_PROVIDER is omitted; otherwise email is disabled.
Incomplete credentials or an invalid sender address disable email delivery.
No credentials should ever be checked into Git.

The additional SPACE_NOVA_REGISTRATION_OPEN setting is an independent
fail-closed public signup switch. It is false by default, even if delivery
credentials exist. After successful provider testing, set it to true
to enable public registration. Existing account login is unaffected.

### Verify email delivery privately, without opening registration

Build and deploy the updated OTP release after changing dependencies. The
server must be restarted to read provider environment values. It is not
necessary to change Caddy or Tauri. With the new OTP release running, issue
a one-time test through the service's own running BEAM node:

~~~sh
sudo systemd-run --unit="space-mmo-email-check-$(date +%s)" \
  --wait --pipe --collect \
  --property=User=ubuntu \
  --property=WorkingDirectory=/home/ubuntu/deploy/space_mmo \
  --property=EnvironmentFile=/home/ubuntu/.config/space_mmo.env \
  /home/ubuntu/deploy/space_mmo/bin/space_mmo rpc \
  'IO.inspect(Darkorbit.Email.Probe.send_test("your-inbox@example.com"))'
~~~

Replace the recipient with an inbox you control. Expected result:
{:ok, :accepted} means the configured provider accepted the message, NOT
that the inbox received it. Check the actual inbox and provider delivery
dashboard. {:error, :not_configured} means email is disabled or incomplete;
{:error, :delivery_failed} means the provider rejected the attempt.
The probe exposes neither SMTP credentials nor provider error details.

No admin HTTP route is added. The probe is operator-only and cannot
register users or affect game progress.

### Provider setup still required

The repository cannot create an external SMTP account, verify domain DNS,
approve Amazon SES production access, or supply credentials. Those are
provider-side actions. Once verified delivery succeeds, set
SPACE_NOVA_REGISTRATION_OPEN=true, restart the service, then test actual
pilot onboarding through the installed Tauri production client. Keep the
existing 24-hour verification expiry and resend throttles.

Avoid putting secrets in chat, tickets, GitHub commits or shell history.
An email provider will generally require a sender domain under your control.
The existing spacenova.ddns.net game hostname does not itself demonstrate
ownership of mail-related DNS records.
