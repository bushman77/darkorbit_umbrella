#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod network;
mod native_loopback;

use tauri::Manager;
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons, MessageDialogKind};
use tauri_plugin_updater::UpdaterExt;

// All update actions execute natively in Rust. No Tauri updater, dialog or
// process permissions are granted to either the launcher or remote web pages.
fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            network::get_network_settings,
            network::save_network_settings,
            network::restart_client,
            native_loopback::native_loopback_post,
        ])
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .setup(|app| {
            // Create the installed production webview using its bundled window
            // configuration, with an optional native SOCKS5 tunnel override.
            // Never expose this control to the remote page or enable it by default.
            let window_config = &app.config().app.windows[0];
            let mut window = tauri::WebviewWindowBuilder::from_config(app.handle(), window_config)?;

            if let Some(proxy_url) = network::startup_proxy(app.handle()) {
                window = window.proxy_url(proxy_url.parse()?);
                eprintln!("Space Nova: native webview proxy enabled ({proxy_url})");
            }

            window.build()?;

            let handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                if let Err(error) = check_for_updates(handle).await {
                    // Never block game access when GitHub Releases is unreachable
                    // (for example, on a restricted institutional network).
                    eprintln!("Space Nova update check unavailable: {error}");
                }
            });
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("failed to launch the Space Nova desktop client");
}

async fn check_for_updates(app: tauri::AppHandle) -> tauri_plugin_updater::Result<()> {
    // The Linux updater is intended for self-contained AppImages, not .deb
    // installations managed by apt/dpkg.
    #[cfg(target_os = "linux")]
    if std::env::var_os("APPIMAGE").is_none() {
        return Ok(());
    }

    let updater = app
        .updater_builder()
        .timeout(std::time::Duration::from_secs(15))
        .build()?;

    if let Some(update) = updater.check().await? {
        let version = update.version.clone();
        let prompt_handle = app.clone();

        app.dialog()
            .message(format!(
                "Space Nova {version} is available. Download and install the signed update now?"
            ))
            .title("Space Nova update available")
            .buttons(MessageDialogButtons::OkCancel)
            .show(move |accepted| {
                if !accepted {
                    return;
                }

                let handle = prompt_handle.clone();
                tauri::async_runtime::spawn(async move {
                    let result = update.download_and_install(|_, _| {}, || {}).await;

                    match result {
                        Ok(()) => {
                            // Windows exits automatically when NSIS begins installing.
                            #[cfg(not(target_os = "windows"))]
                            handle.restart();
                        }
                        Err(error) => {
                            eprintln!("Space Nova update installation failed: {error}");
                            handle
                                .dialog()
                                .message(
                                    "The signed update could not be installed. The current client has not been replaced.",
                                )
                                .kind(MessageDialogKind::Error)
                                .title("Space Nova update failed")
                                .show(|_| {});
                        }
                    }
                });
            });
    }

    Ok(())
}
