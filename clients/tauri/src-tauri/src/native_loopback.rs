//! Restricted bridge for native UI -> local development Phoenix JSON requests.
//! WebKitGTK may reject cross-origin localhost fetch from tauri://localhost.
//! This command never accepts arbitrary hosts, schemes or paths.
use serde::Serialize;
use std::time::Duration;
use tauri::WebviewWindow;

#[derive(Serialize)]
pub struct NativeJsonResponse {
    status: u16,
    body: String,
}

fn route_allowed(route: &str) -> bool {
    matches!(
        route,
        "/api/native/probe"
            | "/api/native/login"
            | "/api/native/refresh"
            | "/api/native/logout"
    )
}

// Tauri's local-only permission controls origin. This is a separate
// defense-in-depth check for which window is invoking the command.
fn main_window_allowed(label: &str) -> bool {
    label == "main"
}

#[tauri::command]
pub async fn native_loopback_post(
    window: WebviewWindow,
    route: String,
    payload: serde_json::Value,
    bearer: Option<String>,
) -> Result<NativeJsonResponse, String> {
    // The command's Tauri capability is local-only and excludes remote origins.
    // Do not reuse network::require_local here: that launcher-settings check
    // rejects the local game.html document on some WebKitGTK installations.
    // Still restrict this bridge to the application's single main webview.
    if !main_window_allowed(window.label()) {
        return Err("Native loopback requests require the Space Nova main window.".into());
    }
    if !route_allowed(&route) {
        return Err("Native request route is not permitted.".into());
    }
    let encoded = serde_json::to_vec(&payload).map_err(|_| "Invalid JSON payload.")?;
    if encoded.len() > 4096 {
        return Err("Native request payload is too large.".into());
    }
    if bearer.is_some() && !matches!(route.as_str(), "/api/native/refresh" | "/api/native/logout") {
        return Err("Bearer authorization is not permitted for this route.".into());
    }
    if let Some(ref token) = bearer {
        if token.is_empty()
            || token.len() > 4096
            || !token.bytes().all(|b| b.is_ascii_graphic())
        {
            return Err("Invalid native bearer token.".into());
        }
    }

    // Fixed loopback target. Never follow redirects or use environment/SOCKS5
    // proxy settings for local requests. Credentials are never logged/stored.
    let client = reqwest::Client::builder()
        .no_proxy()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(Duration::from_secs(12))
        .build()
        .map_err(|e| format!("Cannot initialize local HTTP transport: {e}"))?;
    let mut request = client
        .post(format!("http://127.0.0.1:4000{route}"))
        .header("content-type", "application/json")
        .header("origin", "tauri://localhost")
        .body(encoded);
    if let Some(token) = bearer {
        request = request.header("authorization", format!("Bearer {token}"));
    }
    let response = request
        .send()
        .await
        .map_err(|e| format!("Local Phoenix request failed: {e}"))?;
    let status = response.status().as_u16();
    let body = response
        .text()
        .await
        .map_err(|e| format!("Cannot read local Phoenix response: {e}"))?;
    if body.len() > 65536 {
        return Err("Local Phoenix response exceeds size limit.".into());
    }
    Ok(NativeJsonResponse { status, body })
}

#[cfg(test)]
mod tests {
    use super::{main_window_allowed, route_allowed};

    #[test]
    fn bridge_requires_the_main_application_window() {
        assert!(main_window_allowed("main"));
        assert!(!main_window_allowed("remote"));
        assert!(!main_window_allowed("popup"));
        assert!(!main_window_allowed(""));
    }

    #[test]
    fn only_four_native_json_routes_are_whitelisted() {
        for route in [
            "/api/native/probe",
            "/api/native/login",
            "/api/native/refresh",
            "/api/native/logout",
        ] {
            assert!(route_allowed(route), "{route}");
        }
        for route in [
            "/",
            "/api/native/other",
            "/api/native/login?other=true",
            "http://example.org/",
            "/api/native/../admin",
        ] {
            assert!(!route_allowed(route), "{route}");
        }
    }
}
