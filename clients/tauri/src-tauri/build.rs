fn main() {
    tauri_build::try_build(
        tauri_build::Attributes::new().app_manifest(
            tauri_build::AppManifest::new().commands(&[
                "get_network_settings",
                "save_network_settings",
                "restart_client",
            ]),
        ),
    )
    .expect("Unable to generate local-network command permissions");
}
