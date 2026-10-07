fn main() {
    println!("cargo:rerun-if-env-changed=SEMESTR_APP_URL");
    tauri_build::build()
}
