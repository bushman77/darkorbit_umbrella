# Space Nova desktop launcher (Tauri 2)

This is the first, server-hosted Space Nova desktop client for Pop!_OS and
other supported Linux desktops. The launcher UI is bundled in the app, but
the game remains served over HTTPS from the authoritative Phoenix server.

By default, the launcher connects to `https://spacenova.ddns.net`.
It offers **Launch game** (`/play`), **Create pilot account** (`/register`),
and **Visit homepage** (`/`). A previous server origin saved inside the
client's local storage takes precedence; edit the server field to switch
between local and remote environments.

There is also a **Use local server** shortcut for `http://127.0.0.1:4000`.
The launcher validates that all remote servers use HTTPS, and refuses
credentials, paths, query strings and fragments in the server-origin field.
It navigates the *top-level webview*, so Phoenix handles the session cookie,
CSRF token, LiveView and `/socket` game channel normally. Remote HTML and
JavaScript receive **no native Tauri capabilities**.

The desktop client does not embed the Elixir server or PostgreSQL. It also
does not yet package the Three.js cockpit assets locally. A standalone
asset-bundled game renderer is a future milestone.

## Local development on Pop!_OS

Install the Linux build dependencies (only needed once):

```sh
sudo apt update
sudo apt install -y libwebkit2gtk-4.1-dev build-essential curl wget file \
  libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev
```

Install Rust via https://rustup.rs/ and Node.js / npm as necessary.

To test the registration flow against your local Phoenix server:

```sh
cd ~/darkorbit_umbrella
DARKORBIT_LOOPBACK_ONLY=1 DARKORBIT_DEV_HTTPS=0 mix phx.server
```

In a second terminal:

```sh
cd ~/darkorbit_umbrella/clients/tauri
npm install
npm test
npm run dev
```

Select **Use local server** and then **Create pilot account**. The local
verification email is displayed in the development mailbox at
`http://127.0.0.1:4000/dev/mailbox`. Follow its link and sign in. The
browser-login session is separate from a normal Firefox profile.

You can also enter `https://spacenova.ddns.net` to access the deployed site.
Registration there is disabled until production email delivery is configured.

For local TLS, set up mkcert as documented in the umbrella project and run
Phoenix with `DARKORBIT_DEV_HTTPS=1`, then enter `https://localhost:4001`.
Do not send HTTPS requests to the HTTP-only port 4000.

## Easy desktop build and release manager

From the root of the `sbs` checkout on Pop!_OS:

```sh
cd ~/darkorbit_umbrella
./scripts/space-nova
```

The menu can run tests, build Linux installers, trigger a Windows `.exe`
build on GitHub Actions, download its installer, view build status, prepare
a version bump, or trigger a signed release. Each action is also available
directly as a command:

```sh
./scripts/space-nova test
./scripts/space-nova linux
./scripts/space-nova windows
./scripts/space-nova status
./scripts/space-nova download
./scripts/space-nova version 0.3.1
./scripts/space-nova publish 0.3.1
```

For GitHub commands install and authenticate the GitHub CLI once:

```sh
sudo apt install gh
gh auth login
```

`download` selects only a successful Windows installer for the checked-out
commit, then extracts it into `clients/tauri/dist/windows-X.Y.Z/`. If GitHub
is still building, inspect `status` and retry `download` after success.

For signed updates, run `version X.Y.Z` and follow the printed test, commit,
and push instructions before running `publish X.Y.Z`. This second command
checks for uncommitted tracked edits, is synchronized to `origin/sbs`, and
has no existing release of the same version. It asks you to type `PUBLISH`
before triggering the signed workflow. Configure `TAURI_SIGNING_PRIVATE_KEY`
and `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` **only as GitHub Actions secrets**.
The helper never reads or prints them, and ordinary Windows test installers
do not require signing credentials. Version `0.3.0` may be published using
`./scripts/space-nova publish 0.3.0` once its secrets are configured.

## Build and distribute

```sh
cd ~/darkorbit_umbrella
git pull --ff-only origin sbs
cd clients/tauri
npm install
npm test
npm run build
```

Linux installers are placed in:

- `src-tauri/target/release/bundle/deb/*.deb`
- `src-tauri/target/release/bundle/appimage/*.AppImage`

The `sbs` workflow also uploads both installers as a GitHub Actions artifact
when client files are changed. GitHub Actions artifacts may require sign-in
and are not the same as a public release download.

Linux Tauri uses WebKitGTK. Verify that login, browser navigation, Three.js
WebGL, fullscreen, pointer lock and SBS rendering work on the real laptop.

If an NVIDIA / Wayland system produces flickering or a blank WebKit window,
try `WEBKIT_DISABLE_DMABUF_RENDERER=1 npm run dev` as a diagnostic only.

To keep Rust build output outside the Phoenix watcher scope:

```sh
export CARGO_TARGET_DIR="$HOME/.cache/space-nova-tauri-target"
```

Setting `CARGO_TARGET_DIR` changes the binary and installer output
directories. Run `npm run build` without it if you want the default paths
shown above.

## Identifier and upgrade compatibility

The Tauri application identifier remains `game.sbs.space` for compatibility
with previously installed test builds. The visible product, launcher and
package name are now **Space Nova**, version `0.2.0`. Existing installed
launcher builds do not update automatically.

## Build the Windows x64 installer (without owning a Windows machine)

The dedicated GitHub Actions workflow at
`.github/workflows/space-nova-windows.yml` builds an NSIS
`Space Nova_*_x64-setup.exe` on a hosted Windows runner.
The Linux workflow and its `.deb` / `.AppImage` outputs remain unchanged.

1. Push changes to the existing `sbs` branch, or manually run the
   **Build Space Nova Windows installer** workflow from the GitHub Actions tab.
2. Wait for **Test launcher** and **Build Windows NSIS installer** to pass.
3. Download the `space-nova-windows-x86_64` artifact from the workflow run.
4. Extract the artifact zip and share the resulting setup EXE with your Windows
   tester. The EXE installs the webview launcher; it does not install the game
   server or PostgreSQL.

Windows uses Microsoft Edge WebView2. The NSIS installer defaults to per-user
installation. It can install WebView2 if absent, subject to connectivity.
Keep the Tauri `identifier` stable so later releases can update the same app.

**First-install trust:** The test NSIS installer is currently unsigned with a
Windows Authenticode certificate, so SmartScreen may warn or an organization
policy may block installation. Do not ask users to disable security protections.
For public distribution, obtain an appropriate Windows code-signing
certificate. This is **separate** from Tauri updater artifact signatures.

### Native updater support in 0.3.0

The public key in `tauri.conf.json` is the public key generated by the Space
Nova operator; no private signing materials belong in this repository. From
version 0.3.0, Windows launches check the latest GitHub Release manifest
(`latest.json`) at startup and offer an explicit **OK / Cancel** confirmation
before installing a signed update. The native Rust process owns this flow and
only accepts Tauri-signed artifacts. There is **no Tauri IPC updater permission**
for the embedded game website.

The update check is best-effort and times out quickly. A restrictive network
blocking GitHub does not block startup or gameplay. The local/SSH route to
Phoenix is unaffected.

For Linux, **AppImages** can participate in native updates. `.deb` packages
remain updated through `apt` or manual package installation. For Windows,
Tauri's updater invokes the NSIS installer and exits the old app. Keep the Tauri
identifier unchanged for upgrade compatibility.

Existing 0.2.0 clients have no updater built in: install version 0.3.0
manually **once**. After a later, newer signed release is published, 0.3.0 can
offer to install it. Updating the Phoenix website/game does **not** require
a new native launcher build.

### Publishing an authenticated desktop update

**Do not share your private signing key or password with anyone.** Configure
these GitHub Actions repository secrets privately in Settings → Secrets and
variables → Actions:

- `TAURI_SIGNING_PRIVATE_KEY`: exact private key contents from
  `~/.tauri/space-nova.key` (not the public key)
- `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`: the passphrase chosen when generating
  the signing key

GitHub's public Actions jobs still produce ordinary unsigned **test**
installers with `npm run build`. Only the separate,
operator-triggered **Publish signed Space Nova desktop release** workflow
receives the signing secrets and enables the optional
`src-tauri/tauri.updater.conf.json` build overlay.

To publish a version:

1. Confirm both normal Linux and Windows jobs are green on `sbs`.
2. Bump `version` together in `tauri.conf.json`, `Cargo.toml` and
   `package.json`. Change the verification test if needed.
3. In GitHub Actions, run **Publish signed Space Nova desktop release**
   on branch `sbs` and enter the matching version (for example `0.3.0`).
4. The workflow signs Windows NSIS `.exe` and Linux `.AppImage`
   independently, generates a single manifest with the literal `.sig` contents,
   then atomically publishes the bundles, signatures and `latest.json` to
   the `vX.Y.Z` GitHub Release. An incomplete build cannot publish a manifest.
5. Test an **actual update** from 0.3.0 to a future 0.3.1 before advertising
   native automatic upgrades. Publishing 0.3.0 alone does not prompt 0.3.0
   clients to install anything.

**Security boundaries:** Updates are accepted only over HTTPS and verified
against the embedded signing public key. No privileged Tauri operations are
available to server-hosted web pages. This signing system is separate from
Windows Authenticode certificates (needed for trusted Windows publisher
reputation) and separate from the TLS configuration on the EC2 game server.

The workflow is manual; merely adding your GitHub Secrets will not
automatically publish any update.
