#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    // Same-origin web UI: the OS WebView holds an HttpOnly session cookie.
    // No native commands, token storage, filesystem or shell access are exposed.
    let app_url = url::Url::parse(option_env!("SEMESTR_APP_URL").unwrap_or("http://localhost:5173"))
        .expect("SEMESTR_APP_URL must be a valid URL");
    assert!(app_url.scheme() == "https" ||
        (app_url.scheme() == "http" && matches!(app_url.host_str(), Some("localhost" | "127.0.0.1" | "[::1]"))),
        "Use HTTPS, except on localhost");
    let allowed_origin = app_url.origin();
    tauri::Builder::default()
        .setup(move |app| {
            tauri::WebviewWindowBuilder::new(app, "main", tauri::WebviewUrl::External(app_url))
                .title("Семестр")
                .inner_size(1440.0, 920.0)
                .min_inner_size(390.0, 650.0)
                .on_new_window(|url, _features| {
                    if matches!(url.scheme(), "https" | "http") && url.username().is_empty() && url.password().is_none() {
                        let _ = open::that_detached(url.as_str());
                    }
                    tauri::webview::NewWindowResponse::Deny
                })
                .on_navigation(move |url| url.origin() == allowed_origin)
                .build()?;
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("Could not start Semestr");
}
