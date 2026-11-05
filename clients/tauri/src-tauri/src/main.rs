#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    // The local launcher navigates to the public Space Nova pages or /play.
    // Server-hosted pages receive no native Tauri commands or OS capabilities.
    tauri::Builder::default()
        .run(tauri::generate_context!())
        .expect("failed to launch the Space Nova desktop client");
}
