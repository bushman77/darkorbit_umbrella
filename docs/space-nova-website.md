# Space Nova website: landing page and pilot registration

The public homepage at `/` introduces Space Nova, distinguishes current playtest
features from planned work, and links to browser gameplay and registration.
The original illustration at
`apps/darkorbit_web/priv/static/images/landing/sol-approach.svg`
is concept artwork, **not** a gameplay screenshot.

## Routes

- `GET /`: public Space Nova landing page.
- `GET /login`, `POST /login`: existing verified pilot login.
- `GET /register`, `POST /register`: new pilot registration.
- `GET /register/success`: confirmation email instructions.
- `GET /verify-account?id=...&token=...`: validates the emailed one-use
  verification secret and activates the account.
- `GET /play`: existing authenticated browser client, unchanged.

Registration uses `Darkorbit.Accounts.register_account/1`, which creates a pilot,
starter Sunracer, equipment, settings, title and two loadouts atomically.
Public parameters cannot set credits, ship ID, faction, verification status or
other server-owned progression fields. A registered account cannot log in until
`Accounts.verify_account/2` accepts its email verification secret.

## Local development

Development registration uses `Swoosh.Adapters.Local`. Start Phoenix and
open `/register`; the confirmation message is captured in the local Swoosh
mailer rather than sent to the outside world. Existing `Swoosh.Adapters.Test`
is used by controller tests.

Run:

```sh
cd ~/darkorbit_umbrella
mix test apps/darkorbit_web/test/darkorbit_web/controllers/page_controller_test.exs \
  apps/darkorbit_web/test/darkorbit_web/controllers/registration_controller_test.exs \
  apps/darkorbit_web/test/darkorbit_web/controllers/session_controller_test.exs
mix format --check-formatted
```

Then build new styles and static asset digests for the production release:

```sh
MIX_ENV=prod mix compile
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release space_mmo --overwrite
```

The homepage and registration templates use Tailwind classes; rebuilding
only the BEAM release without updating the CSS/static manifest is insufficient.

## Production email and signup activation

Production public signup is intentionally **closed by default** so pilots
cannot create an account that has no working verification channel.

The project already has Swoosh and its Req client; no additional packages
are needed for the Resend adapter. Configure the following in the server's
private `space_mmo.env` (not in Git), using a sender address on a domain
verified with the mail provider:

```dotenv
RESEND_API_KEY=<set-in-private-server-environment>
REGISTRATION_FROM_EMAIL=pilots@your-verified-domain.example
```

Both variables are required for production registration to become available.
Registration email is then sent through `Swoosh.Adapters.Resend`.
Use your real provider credentials and a sender you control; the sample
address is a placeholder. The default `spacenova.ddns.net` hostname does not
automatically prove domain ownership for outbound mail.

Verify sender-domain DNS records, delivery and link redirects before opening
the site to public signups. Only the operator should edit the private
`~/.config/space_mmo.env` file; never publish the API key. After a release
update, restart the `space-mmo` service to load these runtime settings.

The page remains visible but displays a registration-closed notice when
the variables are absent. Failed email delivery leaves the created account
unverified and reports the problem to the operator; it does not
silently grant access.

## Before a wider public launch

- Add per-IP/device signup throttling at the trusted reverse proxy or an
  authoritative application boundary before accepting untrusted mass signups.
- Add a resend-verification flow with a cooldown for transient delivery failure.
- Add account recovery/password reset, token expiration and cleanup of stale
  unverified registrations.
- Replace concept artwork with genuine captured game screenshots when ready.
- Keep the existing browser client and Tauri prototype usable while separating
  downloaded game assets from the authoritative Elixir server.

The `sbs` branch is used throughout. No new branch or database migration is
required for this change.
