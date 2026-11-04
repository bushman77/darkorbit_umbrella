#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    // The packaged launcher navigates to Phoenix /play. No native commands
    // or OS capabilities are exposed to server-delivered game JavaScript.
    tauri::Builder::default()
        .run(tauri::generate_context!())
        .expect("failed to launch the SBS Space desktop client");
}
