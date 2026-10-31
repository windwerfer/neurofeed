//! NeuroFeed for Android: the same eframe app as desktop, started by
//! `GameActivity` (android-activity), plus the JNI glue the Kotlin side
//! calls (`org.neurofeed.android.MainActivity`). Host builds are empty.

#[cfg(target_os = "android")]
mod android;
