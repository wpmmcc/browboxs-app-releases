//! browboxs desktop shell — single product UI (no product WebUI).
//! Starts local Agent; single-instance · splash · system tray.

use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;
use std::time::Duration;
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Manager, WindowEvent,
};

struct AgentProc(Mutex<Option<Child>>);

fn default_data_dir() -> PathBuf {
    if let Ok(root) = std::env::var("BROWBOX_INSTALL_ROOT") {
        return PathBuf::from(root).join("data");
    }
    if let Ok(p) = std::env::var("BROWBOX_AGENT_DATA") {
        let pb = PathBuf::from(p);
        if let Some(parent) = pb.parent() {
            return parent.to_path_buf();
        }
        return pb;
    }
    if let Some(bd) = directories::BaseDirs::new() {
        let local = bd.home_dir().join(".local/opt/browboxs/data");
        if local.exists() {
            return local;
        }
        return bd.home_dir().join(".browboxs");
    }
    PathBuf::from(".browboxs")
}

fn find_agent_bin() -> Option<PathBuf> {
    if let Ok(p) = std::env::var("BROWBOX_AGENT_BIN") {
        let pb = PathBuf::from(p);
        if pb.exists() {
            return Some(pb);
        }
    }
    if let Ok(root) = std::env::var("BROWBOX_INSTALL_ROOT") {
        for name in ["browboxs-agent", "browboxs-agent.exe"] {
            let c = PathBuf::from(&root).join("bin").join(name);
            if c.exists() {
                return Some(c);
            }
        }
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            for name in [
                "browboxs-agent",
                "browboxs-agent.exe",
                "browboxs-agent-x86_64-unknown-linux-gnu",
                "browboxs-agent-aarch64-unknown-linux-gnu",
            ] {
                let c = dir.join(name);
                if c.exists() {
                    return Some(c);
                }
            }
            for rel in [
                "../../../../../target/release/browboxs-agent",
                "../../../../../target/debug/browboxs-agent",
            ] {
                if let Ok(p) = dir.join(rel).canonicalize() {
                    if p.exists() {
                        return Some(p);
                    }
                }
            }
        }
    }
    let home = directories::BaseDirs::new().map(|b| b.home_dir().to_path_buf());
    let mut candidates = vec![
        PathBuf::from("/home/john/browboxs-v2/target/release/browboxs-agent"),
        PathBuf::from("/home/john/browboxs-v2/target/debug/browboxs-agent"),
        PathBuf::from("/home/john/browboxs-v2/.install/bin/browboxs-agent"),
    ];
    if let Some(h) = home {
        candidates.push(h.join(".local/opt/browboxs/bin/browboxs-agent"));
    }
    for p in candidates {
        if p.exists() {
            return Some(p);
        }
    }
    None
}

fn find_engines_dir() -> PathBuf {
    if let Ok(p) = std::env::var("BROWBOX_ENGINES_DIR") {
        return PathBuf::from(p);
    }
    if let Ok(root) = std::env::var("BROWBOX_INSTALL_ROOT") {
        let p = PathBuf::from(root).join("engines");
        if p.exists() {
            return p;
        }
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            let p = dir.join("../engines");
            if let Ok(c) = p.canonicalize() {
                if c.exists() {
                    return c;
                }
            }
        }
    }
    if let Some(bd) = directories::BaseDirs::new() {
        let p = bd.home_dir().join(".local/opt/browboxs/engines");
        if p.exists() {
            return p;
        }
    }
    for c in [
        "/home/john/browboxs-v2/packaged/engines",
        "/home/john/browboxs-v2/.install/engines",
    ] {
        let p = PathBuf::from(c);
        if p.exists() {
            return p;
        }
    }
    PathBuf::from("packaged/engines")
}

fn resolve_agent_data() -> PathBuf {
    if let Ok(p) = std::env::var("BROWBOX_AGENT_DATA") {
        return PathBuf::from(p);
    }
    // Product default: <install>/data/agent (NOT nested data/agent/agent).
    default_data_dir().join("agent")
}

fn spawn_agent() -> Result<Child, String> {
    // If Local API is already healthy (lab e2e / prior instance), do not spawn a second
    // process: a failed bind still used to rewrite local_session.token and break auth.
    if wait_agent_health(400) {
        eprintln!("[browboxs] agent already healthy on port — skip spawn");
        return Err("agent already running (reuse existing)".into());
    }
    let bin = find_agent_bin().ok_or_else(|| {
        "browboxs-agent not found; build crates and set BROWBOX_AGENT_BIN".to_string()
    })?;
    let engines = find_engines_dir();
    let log = default_data_dir().join("logs");
    let _ = std::fs::create_dir_all(&log);
    let log_file = std::fs::File::create(log.join("agent.log")).ok();
    let mut cmd = Command::new(&bin);
    let agent_data = resolve_agent_data();
    let _ = std::fs::create_dir_all(&agent_data);
    if let Ok(root) = std::env::var("BROWBOX_INSTALL_ROOT") {
        cmd.env("BROWBOX_INSTALL_ROOT", &root);
    }
    cmd.env("BROWBOX_AGENT_DATA", &agent_data)
        .env(
            "BROWBOX_AGENT_PORT",
            std::env::var("BROWBOX_AGENT_PORT").unwrap_or_else(|_| "18910".into()),
        )
        .env("BROWBOX_AGENT_BIND", "127.0.0.1")
        .env("BROWBOX_ENGINES_DIR", &engines)
        .env("BROWBOX_ALLOW_NO_SANDBOX", "1")
        .env("BROWBOX_HEADLESS", "0")
        .env("GDK_BACKEND", "x11")
        .env("MOZ_ENABLE_WAYLAND", "0")
        .env(
            "DISPLAY",
            std::env::var("DISPLAY").unwrap_or_else(|_| ":0".into()),
        )
        .env_remove("BROWBOX_UI_DIR")
        .env_remove("BROWBOX_SERVE_UI")
        .env_remove("BROWBOX_INSECURE_NO_AUTH")
        .stdin(Stdio::null());
    if let Some(f) = log_file {
        cmd.stdout(Stdio::from(f.try_clone().unwrap_or(f)))
            .stderr(Stdio::from(
                std::fs::File::create(log.join("agent.err.log")).unwrap_or_else(|_| {
                    std::fs::File::create("/dev/null").expect("null")
                }),
            ));
    } else {
        cmd.stdout(Stdio::null()).stderr(Stdio::null());
    }
    cmd.spawn()
        .map_err(|e| format!("spawn agent {}: {e}", bin.display()))
}

fn wait_agent_health(timeout_ms: u64) -> bool {
    let port = std::env::var("BROWBOX_AGENT_PORT").unwrap_or_else(|_| "18910".into());
    let url = format!("http://127.0.0.1:{port}/v1/health");
    let start = std::time::Instant::now();
    while start.elapsed() < Duration::from_millis(timeout_ms) {
        if let Ok(resp) = ureq_get_ok(&url) {
            if resp {
                return true;
            }
        }
        std::thread::sleep(Duration::from_millis(150));
    }
    false
}

/// Minimal GET without pulling reqwest — use std::process curl if needed, or TCP connect.
fn ureq_get_ok(url: &str) -> Result<bool, ()> {
    // Prefer curl (always available on Linux packagers)
    let out = Command::new("curl")
        .args(["-fsS", "--max-time", "1", url])
        .output()
        .map_err(|_| ())?;
    if !out.status.success() {
        return Ok(false);
    }
    let s = String::from_utf8_lossy(&out.stdout);
    Ok(s.contains("\"ok\":true") || s.contains("\"ok\": true"))
}

fn kill_agent(app: &tauri::AppHandle) {
    if let Some(state) = app.try_state::<AgentProc>() {
        if let Ok(mut g) = state.0.lock() {
            if let Some(mut c) = g.take() {
                let _ = c.kill();
            }
        }
    }
}

fn brand_icon() -> Option<tauri::image::Image<'static>> {
    tauri::image::Image::from_bytes(include_bytes!("../icons/128x128.png")).ok()
}

fn apply_window_icon(app: &tauri::AppHandle) {
    let Some(icon) = brand_icon().or_else(|| app.default_window_icon().cloned()) else {
        return;
    };
    for label in ["main", "splash"] {
        if let Some(w) = app.get_webview_window(label) {
            let _ = w.set_icon(icon.clone());
        }
    }
}

fn show_main(app: &tauri::AppHandle) {
    apply_window_icon(app);
    if let Some(w) = app.get_webview_window("main") {
        // Do not reset size/position — user move/resize must persist (normal WM habit).
        let _ = w.show();
        let _ = w.set_focus();
        let _ = w.unminimize();
    }
    if let Some(s) = app.get_webview_window("splash") {
        // WebDriver attaches to the first window. Closing splash races
        // tauri-driver's getWindowHandle (seen on ubuntu-arm). Hide instead
        // when BROWBOX_E2E_KEEP_SPLASH=1; production still closes.
        if std::env::var("BROWBOX_E2E_KEEP_SPLASH").ok().as_deref() == Some("1") {
            let _ = s.hide();
        } else {
            let _ = s.close();
        }
    }
}

#[tauri::command]
fn agent_url() -> String {
    let port = std::env::var("BROWBOX_AGENT_PORT").unwrap_or_else(|_| "18910".into());
    format!("http://127.0.0.1:{port}")
}

fn read_token_from_dir(dir: &std::path::Path) -> Option<String> {
    let t = dir.join("local_session.token");
    if let Ok(s) = std::fs::read_to_string(&t) {
        let s = s.trim().to_string();
        if !s.is_empty() {
            return Some(s);
        }
    }
    let j = dir.join("local_api.json");
    if let Ok(raw) = std::fs::read_to_string(&j) {
        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&raw) {
            if let Some(tok) = v.get("token").and_then(|x| x.as_str()) {
                let tok = tok.trim();
                if !tok.is_empty() {
                    return Some(tok.to_string());
                }
            }
        }
    }
    None
}

fn token_accepted(url: &str, token: &str) -> bool {
    let out = Command::new("curl")
        .args([
            "-sS",
            "-o",
            "/dev/null",
            "-w",
            "%{http_code}",
            "--max-time",
            "2",
            "-H",
            &format!("Authorization: Bearer {token}"),
            &format!("{url}/v1/proxies"),
        ])
        .output();
    match out {
        Ok(o) => String::from_utf8_lossy(&o.stdout).trim() == "200",
        Err(_) => false,
    }
}

#[tauri::command]
fn local_api_credentials() -> Result<serde_json::Value, String> {
    let port = std::env::var("BROWBOX_AGENT_PORT").unwrap_or_else(|_| "18910".into());
    let url = format!("http://127.0.0.1:{port}");
    let mut candidates = vec![
        resolve_agent_data(),
        default_data_dir().join("agent"),
        default_data_dir().join("agent").join("agent"),
    ];
    if let Some(home) = directories::BaseDirs::new() {
        let h = home.home_dir();
        candidates.push(h.join(".local/opt/browboxs/data/agent"));
        candidates.push(h.join(".browboxs/agent"));
    }
    let mut seen = std::collections::HashSet::new();
    let mut fallback: Option<(String, PathBuf)> = None;
    for c in &candidates {
        let Some(token) = read_token_from_dir(c) else {
            continue;
        };
        if !seen.insert(token.clone()) {
            continue;
        }
        if fallback.is_none() {
            fallback = Some((token.clone(), c.clone()));
        }
        if token_accepted(&url, &token) {
            return Ok(serde_json::json!({
                "url": url,
                "token": token,
                "data_dir": c.display().to_string(),
                "ui": "desktop_client_only",
            }));
        }
    }
    if let Some((token, found)) = fallback {
        return Ok(serde_json::json!({
            "url": url,
            "token": token,
            "data_dir": found.display().to_string(),
            "ui": "desktop_client_only",
        }));
    }
    Err(format!(
        "local_session.token not found under {:?}",
        candidates
    ))
}

#[tauri::command]
fn product_shape() -> serde_json::Value {
    serde_json::json!({
        "ui": "desktop_client_only",
        "product_webui": false,
        "local_api": "loopback + session token; not a browser console",
        "official_web": "node domain purchase / connection assist only",
        "host_server": "optional, managed inside desktop UI",
        "member_join": "add node domain in desktop UI",
        "shell": {
            "single_instance": true,
            "system_tray": true,
            "splash": true,
        }
    })
}

#[cfg(target_os = "linux")]
fn linux_icon_paths() -> Vec<std::path::PathBuf> {
    let mut out = Vec::new();
    if let Ok(root) = std::env::var("BROWBOX_INSTALL_ROOT") {
        let r = PathBuf::from(root);
        out.push(r.join("share/pixmaps/browboxs.png"));
        out.push(r.join("share/icons/hicolor/256x256/apps/browboxs.png"));
        out.push(r.join("branding/browboxs-256.png"));
    }
    if let Some(home) = directories::BaseDirs::new() {
        let h = home.home_dir();
        out.push(h.join(".local/share/icons/hicolor/256x256/apps/browboxs.png"));
        out.push(h.join(".local/share/pixmaps/browboxs.png"));
    }
    out.push(PathBuf::from(
        "/home/john/browboxs-v2/packaged/branding/browboxs-256.png",
    ));
    out
}

/// Pin X11 WM_CLASS instance to `browboxs` (matches .desktop StartupWMClass).
/// Must run before GTK init (Tauri Builder).
#[cfg(target_os = "linux")]
fn pin_linux_prgname() {
    glib::set_prgname(Some("browboxs"));
    glib::set_application_name("browboxs");
}

#[cfg(target_os = "linux")]
fn apply_linux_default_icon() {
    gtk::Window::set_default_icon_name("browboxs");
    for p in linux_icon_paths() {
        if !p.exists() {
            continue;
        }
        if let Ok(pb) = gdk_pixbuf::Pixbuf::from_file(&p) {
            gtk::Window::set_default_icon(&pb);
            break;
        }
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    #[cfg(target_os = "linux")]
    pin_linux_prgname();

    let builder = tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            // Second launch: focus existing main window (desktop client, not new browser).
            show_main(app);
        }));

    #[cfg(feature = "wdio-e2e")]
    let builder = if std::env::var("TAURI_WEBDRIVER_PORT")
        .ok()
        .filter(|p| !p.is_empty())
        .is_some()
    {
        // Upstream init() falls back to port 4445 even when env is unset — that
        // collides with tauri-driver --native-port. Only attach when CI/tests set it.
        builder.plugin(tauri_plugin_wdio_webdriver::init())
    } else {
        builder
    };

    builder
        .manage(AgentProc(Mutex::new(None)))
        .setup(|app| {
            #[cfg(target_os = "linux")]
            apply_linux_default_icon();

            let handle = app.handle().clone();

            // System tray: show / quit (close main → hide to tray)
            let show_i = MenuItem::with_id(app, "show", "显示工作台", true, None::<&str>)?;
            let quit_i = MenuItem::with_id(app, "quit", "退出 browboxs", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show_i, &quit_i])?;
            apply_window_icon(&handle);
            if let Some(icon) = brand_icon().or_else(|| app.default_window_icon().cloned()) {
                let _tray = TrayIconBuilder::new()
                    .menu(&menu)
                    .tooltip("browboxs 指纹浏览器工作台")
                    .icon(icon)
                    .on_menu_event({
                        let handle = handle.clone();
                        move |app, event| match event.id.as_ref() {
                            "show" => show_main(app),
                            "quit" => {
                                kill_agent(&handle);
                                app.exit(0);
                            }
                            _ => {}
                        }
                    })
                    .on_tray_icon_event(|tray, event| {
                        if let TrayIconEvent::Click {
                            button: MouseButton::Left,
                            button_state: MouseButtonState::Up,
                            ..
                        } = event
                        {
                            show_main(tray.app_handle());
                        }
                    })
                    .build(app)?;
            } else {
                eprintln!("[browboxs] no window icon — system tray skipped");
            }

            // Spawn agent then reveal main (splash window if present)
            match spawn_agent() {
                Ok(child) => {
                    if let Some(state) = app.try_state::<AgentProc>() {
                        *state.0.lock().unwrap() = Some(child);
                    }
                }
                Err(e) => {
                    eprintln!("[browboxs] agent start: {e}");
                }
            }

            let handle2 = handle.clone();
            std::thread::spawn(move || {
                let _ = wait_agent_health(12_000);
                std::thread::sleep(Duration::from_millis(200));
                let h = handle2.clone();
                let _ = handle2.run_on_main_thread(move || {
                    show_main(&h);
                });
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            agent_url,
            local_api_credentials,
            product_shape
        ])
        .on_window_event(|window, event| {
            match event {
                WindowEvent::CloseRequested { api, .. } if window.label() == "main" => {
                    // Minimize to tray — keep agent alive (desktop client behavior)
                    api.prevent_close();
                    let _ = window.hide();
                }
                WindowEvent::Destroyed if window.label() == "main" => {
                    kill_agent(window.app_handle());
                }
                _ => {}
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running browboxs desktop");
}
