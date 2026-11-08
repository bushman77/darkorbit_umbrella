//! Native-only networking preferences. Remote Phoenix pages never receive
//! the Tauri capability for these commands. No SSH credentials are stored.
use serde::{Deserialize, Serialize};
use std::{fs, path::PathBuf};
use tauri::{AppHandle, Manager, WebviewWindow};

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct NetworkSettings {
    pub mode: String,
    pub host: String,
    pub port: u16,
}

impl Default for NetworkSettings {
    fn default() -> Self {
        Self {
            mode: "system".into(),
            host: "127.0.0.1".into(),
            port: 1080,
        }
    }
}

#[derive(Serialize)]
pub struct NetworkView {
    pub saved: NetworkSettings,
    pub forced_ssh_tunnel: bool,
}

fn settings_path(app: &AppHandle) -> Result<PathBuf, String> {
    Ok(app
        .path()
        .app_config_dir()
        .map_err(|error| error.to_string())?
        .join("network.json"))
}

fn validate(settings: &NetworkSettings) -> Result<(), String> {
    if settings.mode != "system" && settings.mode != "socks5" {
        return Err("Choose system networking or SOCKS5.".into());
    }
    if settings.port == 0 {
        return Err("The proxy port must be between 1 and 65535.".into());
    }
    if settings.host.is_empty()
        || settings.host.len() > 253
        || !settings.host.is_ascii()
        || !settings
            .host
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || c == b'.' || c == b'-')
        || (settings.host.starts_with('.') || settings.host.starts_with('-'))
        || (settings.host.ends_with('.') || settings.host.ends_with('-'))
    {
        return Err("Enter a valid DNS hostname or IPv4 proxy address.".into());
    }
    Ok(())
}

fn load(app: &AppHandle) -> Result<NetworkSettings, String> {
    let path = settings_path(app)?;
    let content = match fs::read_to_string(path) {
        Ok(content) => content,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Ok(NetworkSettings::default())
        }
        Err(error) => return Err(error.to_string()),
    };
    let settings: NetworkSettings =
        serde_json::from_str(&content).map_err(|error| error.to_string())?;
    validate(&settings)?;
    Ok(settings)
}

fn save(app: &AppHandle, settings: &NetworkSettings) -> Result<(), String> {
    validate(settings)?;
    let path = settings_path(app)?;
    fs::create_dir_all(path.parent().ok_or("Invalid settings path")?)
        .map_err(|error| error.to_string())?;
    let temp = path.with_extension("json.tmp");
    let bytes = serde_json::to_vec_pretty(settings).map_err(|error| error.to_string())?;
    fs::write(&temp, bytes).map_err(|error| error.to_string())?;
    fs::rename(temp, path).map_err(|error| error.to_string())?;
    Ok(())
}

// Both URLs are Tauri's local packaged-app origins. The production HTTPS
// game page (or any other remote origin) is never allowed to call these.
pub(crate) fn require_local(window: &WebviewWindow) -> Result<(), String> {
    let url = window.url().map_err(|error| error.to_string())?;
    let local = (url.scheme() == "tauri" && url.host_str() == Some("localhost"))
        || (["http", "https"].contains(&url.scheme())
            && url.host_str() == Some("tauri.localhost"));
    if local {
        Ok(())
    } else {
        Err("Networking preferences are available only in the local launcher.".into())
    }
}

pub fn startup_proxy(app: &AppHandle) -> Option<String> {
    // Keep the pre-existing launch flag working exactly as before.
    if std::env::var("SPACE_NOVA_USE_SOCKS_TUNNEL").as_deref() == Ok("1") {
        return Some("socks5://127.0.0.1:1080".into());
    }
    match load(app) {
        Ok(settings) if settings.mode == "socks5" => {
            Some(format!("socks5://{}:{}", settings.host, settings.port))
        }
        Ok(_) => None,
        Err(error) => {
            eprintln!("Space Nova: invalid local network preferences ({error}); using system proxy");
            None
        }
    }
}

#[tauri::command]
pub fn get_network_settings(
    app: AppHandle,
    window: WebviewWindow,
) -> Result<NetworkView, String> {
    require_local(&window)?;
    Ok(NetworkView {
        saved: load(&app)?,
        forced_ssh_tunnel: std::env::var("SPACE_NOVA_USE_SOCKS_TUNNEL").as_deref()
            == Ok("1"),
    })
}

#[tauri::command]
pub fn save_network_settings(
    app: AppHandle,
    window: WebviewWindow,
    settings: NetworkSettings,
) -> Result<(), String> {
    require_local(&window)?;
    save(&app, &settings)
}

#[tauri::command]
pub fn restart_client(app: AppHandle, window: WebviewWindow) -> Result<(), String> {
    require_local(&window)?;
    app.restart();
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn defaults_and_proxy_inputs() {
        assert_eq!(NetworkSettings::default().mode, "system");
        assert!(validate(&NetworkSettings {
            mode: "socks5".into(),
            host: "127.0.0.1".into(),
            port: 1080
        }).is_ok());
        assert!(validate(&NetworkSettings {
            mode: "socks5".into(),
            host: "somewhere@evil".into(),
            port: 1080
        }).is_err());
        assert!(validate(&NetworkSettings {
            mode: "https".into(),
            host: "127.0.0.1".into(),
            port: 1080
        }).is_err());
    }
}
