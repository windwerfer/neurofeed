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
        event_loop_builder: Some(Box::new(move |b| {
            use winit::platform::android::EventLoopBuilderExtAndroid;
            b.with_android_app(app);
        })),
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
    fn take_paused(&self) -> bool {
        PAUSED.swap(false, Ordering::Relaxed)
    }
    fn safe_insets_px(&self) -> [f32; 4] {
        INSETS.each_ref().map(|a| f32::from_bits(a.load(Ordering::Relaxed)))
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
}
