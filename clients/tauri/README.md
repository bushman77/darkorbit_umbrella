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

### Signed updater roadmap (not yet active)

The current `0.2.0` desktop client has no built-in update mechanism.
The native shell must receive a new **manually installed** version before it
can begin using automatic updates. Phoenix-rendered homepage and gameplay
changes already deploy instantly on the server.

Use Tauri 2's official updater plugin for native updates, published as signed
release assets in GitHub Releases rather than served from the budget EC2
instance:

1. Generate a private/public updater signing key pair on a trusted machine,
   using `npx tauri signer generate -w ~/.tauri/space-nova.key`. Securely back up
   the private key; **never commit or share it in messages**. Only the public
   key belongs in `tauri.conf.json`.
2. Install `tauri-plugin-updater` into Rust and decide whether to check on
   native launcher startup or through a native-only action. Avoid exposing
   update commands or Tauri IPC access to server-hosted pages.
3. Set `bundle.createUpdaterArtifacts: true` and configure the
   `plugins.updater.pubkey` and
   `plugins.updater.endpoints` entries to check an HTTPS-hosted
   `latest.json` from GitHub Releases.
4. Supply `TAURI_SIGNING_PRIVATE_KEY` and, if encrypted,
   `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` as **GitHub Actions secrets** on a
   dedicated, access-restricted publish workflow. Never expose private
   signing credentials to pull request builds.
5. Build Windows NSIS `.exe` + `.exe.sig` and Linux AppImage + `.sig`;
   publish a single atomically assembled `latest.json` whose
   `windows-x86_64` and `linux-x86_64` entries each contain a
   matching URL and the **literal signature file contents**.
6. Test upgrading an installed old version to a newer one before releasing
   to other pilots. On Windows Tauri exits the old app when it launches the
   updater installer.

Tauri's updater signature key protects integrity and release authenticity;
Windows Authenticode addresses OS publisher trust / SmartScreen reputation.
Neither replaces HTTPS certificate validity for the live game server.
