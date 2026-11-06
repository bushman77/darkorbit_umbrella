# Space Nova — unified GitHub release runbook

All release changes land on the existing **sbs** branch. No temporary branch
and no automatic EC2 deployment are required. The release manager runs on
Linux; Windows compilation runs in GitHub Actions on Windows.

## Versioning

The single authoritative public release version is the umbrella root
`mix.exs` project's `version:` field, initially aligned to `0.3.1`
to preserve the currently installed Tauri client's upgrade ordering.

Use `./scripts/space-nova version X.Y.Z` to change **only** `mix.exs`.
The release workflow calls `python3 scripts/space-nova-version.py sync`
in isolated Windows/Linux runner checkouts to derive the mandatory Tauri,
Cargo, npm package, and npm lockfile build versions. Those files are build
metadata, not additional independent release versions. The helper also has
offline Python regression tests.

**Release asset filenames deliberately contain no version suffix.** The
GitHub tag, e.g. `v0.3.1`, identifies the revision. OS installation
metadata and signed update manifests still carry a real semantic version.

Artifacts in every versioned GitHub Release:

- `space-nova-server-linux-x64.tar.gz` — Ubuntu 24.04 x86_64 OTP release
- `space-nova-linux-x64.AppImage` and `.AppImage.sig`
- `space-nova-linux-x64.deb`
- `space-nova-windows-x64-setup.exe` and `.exe.sig`
- `latest.json` — Tauri signed-updater manifest
- `SHA256SUMS` — checksums for all other release assets

The Android SBS headset remains a Phoenix-served secure browser experience,
available at `/helmet`; there is no APK in this milestone.

## Publish a release from Pop!_OS

Prerequisites: Git, GitHub CLI (`gh auth login`), a clean `sbs` checkout
synchronized to `origin/sbs`, and the existing Tauri signing credentials
stored as **GitHub Actions repository secrets**:

- `TAURI_SIGNING_PRIVATE_KEY`
- `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`

Never paste these into a shell command, release description, chat message, or
repository file. The private signing key does not belong in source control.

The interactive menu is `./scripts/space-nova`. For a new version:

```sh
cd ~/darkorbit_umbrella
./scripts/space-nova version 0.3.2
git diff -- mix.exs
git add mix.exs
git commit -m "Release Space Nova v0.3.2"
git push origin sbs
./scripts/space-nova release 0.3.2
./scripts/space-nova status
```

The release command asks you to type `PUBLISH`. It dispatches
`.github/workflows/space-nova-release.yml` with the exact branch commit
SHA. It refuses an unsynchronized checkout, unmatched version, existing tag,
or existing GitHub release.

GitHub Actions tests the entire Elixir umbrella, browser JavaScript, and
Tauri launcher. It then builds the server, Windows and Linux installers,
validates signatures and artifacts, and verifies SHA-256 sums. All jobs must
succeed before the publisher creates a **draft** release with all assets and
then publishes it. A failed build cannot publish a new public release.

The publish action never restarts or deploys to EC2.

## Dedicated server

The server build uses OTP/Elixir on Ubuntu 24.04 x86_64, builds/digests
production Phoenix assets, creates `mix release space_mmo`, and validates
the release archive. A release-only entrypoint is provided for migrations:

```sh
space_mmo/bin/space_mmo eval 'Darkorbit.Release.migrate()'
```

The CI server job exercises database migration and HTTPS startup against
a disposable PostgreSQL service with ephemeral TLS credentials. Production
certificates, `DATABASE_URL`, `SECRET_KEY_BASE`, and email credentials
are **not** distributed in the server archive.

Production deployment is a separate, deliberate operation after backups,
migration review and compatibility checks. Running this GitHub publishing
workflow alone does not deploy the server.

## Desktop and updates

Windows uses signed NSIS updater bundles. Linux AppImage supports signed
Tauri updates; the Debian `.deb` installer is updated manually or through
package management. Update signatures remain valid when installers are
copied to stable public filenames. `latest.json` links to the corresponding
assets under the specific release tag, while installed clients check GitHub
Releases' `latest` endpoint.

The existing Tauri identifier `game.sbs.space` is retained. Server-hosted
game UI and SBS headset pages can update with the Phoenix deployment, without
shipping a new native desktop binary.

GitHub release signatures and Windows Authenticode publisher certificates
are separate concerns. An unsigned-in-Authenticode Windows installer may
still prompt Windows SmartScreen.

## Troubleshooting and known limitations

- The usual `mix precommit` alias has pre-existing repository-wide
  formatting drift; the release pipeline runs compilation and full tests
  independently without rewriting unrelated files.
- The official server archive is built on Ubuntu 24.04; running a locally
  built archive on a different Linux distribution is not a supported
  compatibility guarantee.
- CI signing requires properly provisioned GitHub Actions secrets.
- Native Windows/Linux installer behavior and headset pairing still need
  manual smoke testing on representative devices.
- Re-running a release for an existing tag is intentionally rejected.
- If the final publish step fails after creating a draft, inspect and
  manually resolve that draft; do not overwrite a tag or force-push it.
