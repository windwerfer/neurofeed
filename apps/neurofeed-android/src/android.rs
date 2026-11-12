//! Android entry point and JNI bridge.
//!
//! Kotlin → Rust (`MainActivity` natives): `nativeInit` (btleplug/droidplug
//! needs a JNI env on a Java thread with the app class loader), `nativePicked`
//! (file from the system picker), `nativeFolder` (chosen export folder),
//! `nativePaused` (activity went to the background), `nativeInsets`
//! (system-bar insets, so the UI stays out from under them).
//! Rust → Kotlin (activity methods, via `ndk-context`): `pickImport`,
//! `pickFolder`, `exportFile`, `keepScreenOn`.

use jni::objects::{JByteArray, JClass, JObject, JString, JValue};
use jni::{Env, EnvUnowned, JavaVM};
use neurofeed_egui::platform::{self, Platform};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::Mutex;
use winit::platform::android::activity::AndroidApp;

static PICKED: Mutex<Option<(String, Vec<u8>)>> = Mutex::new(None);
static FOLDER: Mutex<Option<String>> = Mutex::new(None);
static PAUSED: AtomicBool = AtomicBool::new(false);
/// System-bar insets in px (left, top, right, bottom), stored as f32 bits.
static INSETS: [AtomicU32; 4] = [AtomicU32::new(0), AtomicU32::new(0), AtomicU32::new(0), AtomicU32::new(0)];
/// Android reported insets at least once (listener or poll).
static REPORTED: AtomicBool = AtomicBool::new(false);
/// The `systemBars | displayCutout` listener delivered: the poll (deprecated
/// system-window insets, no cutout) must not overwrite it.
static FROM_LISTENER: AtomicBool = AtomicBool::new(false);

/// Logcat (tag `neurofeed`) plus a panic hook that logs the panic message,
/// location, thread and a backtrace before the process dies; without it a Rust
/// panic only shows up as a bare SIGABRT. Idempotent: called from `nativeInit`
/// (Java main thread, before `android_main`) and from `android_main`.
fn init_logging() {
    static HOOK: std::sync::Once = std::sync::Once::new();
    android_logger::init_once(android_logger::Config::default().with_max_level(log::LevelFilter::Info).with_tag("neurofeed"));
    HOOK.call_once(|| {
        let prev = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            let thread = std::thread::current();
            let name = thread.name().unwrap_or("<unnamed>");
            let bt = std::backtrace::Backtrace::force_capture();
            log::error!("PANIC on thread '{name}': {info}\n{bt}");
            prev(info);
        }));
    });
}

#[no_mangle]
fn android_main(app: AndroidApp) {
    init_logging();
    // App-private storage: the desktop code resolves its data dir from these.
    if let Some(dir) = app.internal_data_path() {
        std::env::set_var("HOME", &dir);
        std::env::set_var("XDG_DATA_HOME", &dir);
    }
    platform::install(Box::new(Hooks));
    let options = eframe::NativeOptions {
        // eframe >= 0.35 builds the winit event loop itself and needs the app here.
        android_app: Some(app),
        ..Default::default()
    };
    if let Err(e) = eframe::run_native("NeuroFeed", options, Box::new(|cc| Ok(Box::new(neurofeed_egui::NeuroFeedApp::new(cc))))) {
        log::error!("eframe: {e}");
    }
}

/// Run `f` with the activity on a JNI env attached to this thread.
fn with_activity<T>(f: impl FnOnce(&mut Env, &JObject) -> jni::errors::Result<T>) -> Result<T, String> {
    let ctx = ndk_context::android_context();
    // SAFETY: ndk-context hands out the process JavaVM and the activity
    // global ref set up by android-activity; both outlive the app.
    let vm = unsafe { JavaVM::from_raw(ctx.vm().cast()) };
    let raw: jni::sys::jobject = ctx.context().cast();
    vm.attach_current_thread(|env| {
        // SAFETY: see above; the global ref stays valid for the process.
        let activity = unsafe { JObject::from_raw(env, raw) };
        f(env, &activity)
    })
    .map_err(|e: jni::errors::Error| e.to_string())
}

macro_rules! call_void {
    ($name:literal, $sig:literal, $args:expr) => {
        if let Err(e) = with_activity(|env, a| env.call_method(a, jni::jni_str!($name), jni::jni_sig!($sig), $args).map(|_| ())) {
            log::warn!("{}: {e}", $name);
        }
    };
}

struct Hooks;

impl Platform for Hooks {
    fn export(&self, file_name: &str, mime: &str, bytes: Vec<u8>) -> Result<String, String> {
        with_activity(|env, a| {
            let (n, m) = (env.new_string(file_name)?, env.new_string(mime)?);
            let b = env.byte_array_from_slice(&bytes)?;
            let r = env.call_method(
                a,
                jni::jni_str!("exportFile"),
                jni::jni_sig!("(Ljava/lang/String;Ljava/lang/String;[B)Ljava/lang/String;"),
                &[(&n).into(), (&m).into(), (&b).into()],
            )?;
            let s = JString::cast_local(env, r.l()?)?;
            s.try_to_string(env)
        })
    }
    fn pick_import(&self) {
        call_void!("pickImport", "()V", &[]);
    }
    fn take_picked(&self) -> Option<(String, Vec<u8>)> {
        PICKED.lock().ok()?.take()
    }
    fn pick_folder(&self) {
        call_void!("pickFolder", "()V", &[]);
    }
    fn folder_label(&self) -> Option<String> {
        FOLDER.lock().ok()?.clone()
    }
    fn keep_screen_on(&self, on: bool) {
        call_void!("keepScreenOn", "(Z)V", &[JValue::Bool(on)]);
    }
    fn min_top_inset_pt(&self) -> f32 {
        // Only until Android delivered real insets once (then 0 is real, e.g.
        // landscape with the status bar hidden).
        if REPORTED.load(Ordering::Relaxed) {
            0.0
        } else {
            FALLBACK_TOP_PT
        }
    }
    fn take_paused(&self) -> bool {
        PAUSED.swap(false, Ordering::Relaxed)
    }
    fn safe_insets_px(&self) -> [f32; 4] {
        poll_insets();
        INSETS.each_ref().map(|a| f32::from_bits(a.load(Ordering::Relaxed)))
    }
    fn system_dark(&self) -> Option<bool> {
        poll_night();
        match NIGHT.load(Ordering::Relaxed) {
            1 => Some(false),
            2 => Some(true),
            _ => None,
        }
    }
}

/// System dark mode (`Configuration.uiMode & UI_MODE_NIGHT_MASK`): 0 unknown,
/// 1 light, 2 dark. winit reports no theme on Android.
static NIGHT: std::sync::atomic::AtomicU8 = std::sync::atomic::AtomicU8::new(0);

/// Re-read the night mode (at most once a second; the manifest handles
/// `uiMode` changes itself, so the activity is not recreated on a switch).
fn poll_night() {
    static LAST: Mutex<Option<std::time::Instant>> = Mutex::new(None);
    {
        let Ok(mut last) = LAST.lock() else { return };
        if last.is_some_and(|t| t.elapsed() < std::time::Duration::from_secs(1)) {
            return;
        }
        *last = Some(std::time::Instant::now());
    }
    let r = with_activity(|env, a| {
        let res = env.call_method(a, jni::jni_str!("getResources"), jni::jni_sig!("()Landroid/content/res/Resources;"), &[])?.l()?;
        let cfg =
            env.call_method(&res, jni::jni_str!("getConfiguration"), jni::jni_sig!("()Landroid/content/res/Configuration;"), &[])?.l()?;
        env.get_field(&cfg, jni::jni_str!("uiMode"), jni::jni_sig!("I"))?.i()
    });
    match r {
        // UI_MODE_NIGHT_MASK 0x30: NO 0x10, YES 0x20, UNDEFINED 0x00.
        Ok(mode) => {
            let v = match mode & 0x30 {
                0x10 => 1,
                0x20 => 2,
                _ => 0,
            };
            if NIGHT.swap(v, Ordering::Relaxed) != v {
                log::info!("Android night mode: uiMode=0x{mode:x}");
            }
        }
        Err(e) => log::debug!("night mode poll: {e}"),
    }
}

/// Status bar height used when Android reports no insets at all.
const FALLBACK_TOP_PT: f32 = 28.0;

/// Re-read the insets from the decor view (at most every 500 ms): covers a
/// missed / consumed `OnApplyWindowInsetsListener` and rotation changes.
fn poll_insets() {
    if FROM_LISTENER.load(Ordering::Relaxed) {
        return;
    }
    static LAST: Mutex<Option<std::time::Instant>> = Mutex::new(None);
    {
        let Ok(mut last) = LAST.lock() else { return };
        if last.is_some_and(|t| t.elapsed() < std::time::Duration::from_millis(500)) {
            return;
        }
        *last = Some(std::time::Instant::now());
    }
    let r = with_activity(|env, a| {
        let win = env.call_method(a, jni::jni_str!("getWindow"), jni::jni_sig!("()Landroid/view/Window;"), &[])?.l()?;
        let decor = env.call_method(&win, jni::jni_str!("getDecorView"), jni::jni_sig!("()Landroid/view/View;"), &[])?.l()?;
        let ins =
            env.call_method(&decor, jni::jni_str!("getRootWindowInsets"), jni::jni_sig!("()Landroid/view/WindowInsets;"), &[])?.l()?;
        if ins.is_null() {
            return Ok(None);
        }
        let mut v = [0; 4];
        for (slot, m) in v.iter_mut().zip([
            jni::jni_str!("getSystemWindowInsetLeft"),
            jni::jni_str!("getSystemWindowInsetTop"),
            jni::jni_str!("getSystemWindowInsetRight"),
            jni::jni_str!("getSystemWindowInsetBottom"),
        ]) {
            *slot = env.call_method(&ins, m, jni::jni_sig!("()I"), &[])?.i()?;
        }
        Ok(Some(v))
    });
    match r {
        Ok(Some(v)) if v.iter().any(|&x| x > 0) => {
            for (a, x) in INSETS.iter().zip(v) {
                a.store((x.max(0) as f32).to_bits(), Ordering::Relaxed);
            }
            REPORTED.store(true, Ordering::Relaxed);
        }
        Ok(_) => {}
        Err(e) => log::debug!("insets poll: {e}"),
    }
}

fn guard(env: *mut jni::sys::JNIEnv, name: &str, f: impl FnOnce(&mut Env) -> jni::errors::Result<()>) {
    // SAFETY: `env` is the JNIEnv the JVM passed to this native method.
    let mut env = unsafe { EnvUnowned::from_raw(env) };
    let _ = name;
    env.with_env(f).resolve::<jni::errors::LogErrorAndDefault>();
}

#[no_mangle]
pub extern "system" fn Java_org_neurofeed_android_MainActivity_nativeInit(env: *mut jni::sys::JNIEnv, _c: JClass, _ctx: JObject) {
    init_logging();
    guard(env, "btleplug init", |env| {
        match btleplug::platform::init(env) {
            Ok(()) => log::info!("btleplug initialized"),
            Err(e) => log::error!("btleplug init: {e}"),
        }
        Ok(())
    });
}

#[no_mangle]
pub extern "system" fn Java_org_neurofeed_android_MainActivity_nativePicked(
    env: *mut jni::sys::JNIEnv,
    _c: JClass,
    name: JString,
    data: JByteArray,
) {
    guard(env, "picked", |env| {
        let n = name.try_to_string(env)?;
        let b = env.convert_byte_array(&data)?;
        if let Ok(mut p) = PICKED.lock() {
            *p = Some((n, b));
        }
        Ok(())
    });
}

#[no_mangle]
pub extern "system" fn Java_org_neurofeed_android_MainActivity_nativeFolder(env: *mut jni::sys::JNIEnv, _c: JClass, label: JString) {
    guard(env, "folder", |env| {
        let l = label.try_to_string(env)?;
        if let Ok(mut f) = FOLDER.lock() {
            *f = Some(l);
        }
        Ok(())
    });
}

#[no_mangle]
pub extern "system" fn Java_org_neurofeed_android_MainActivity_nativePaused(_env: *mut jni::sys::JNIEnv, _c: JClass) {
    PAUSED.store(true, Ordering::Relaxed);
}

#[no_mangle]
pub extern "system" fn Java_org_neurofeed_android_MainActivity_nativeInsets(
    _env: *mut jni::sys::JNIEnv,
    _c: JClass,
    left: jni::sys::jint,
    top: jni::sys::jint,
    right: jni::sys::jint,
    bottom: jni::sys::jint,
) {
    for (a, v) in INSETS.iter().zip([left, top, right, bottom]) {
        a.store((v.max(0) as f32).to_bits(), Ordering::Relaxed);
    }
    REPORTED.store(true, Ordering::Relaxed);
    FROM_LISTENER.store(true, Ordering::Relaxed);
}
