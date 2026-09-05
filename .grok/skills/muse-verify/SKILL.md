---
name: muse-verify
description: >
  After Dart or Rust edits in Muse ML, run flutter analyze and the right
  flutter test / cargo test commands, including the host .so and
  rust/target/release loader trap. Use when verifying a change or running tests.
---

Do not start `flutter run` unless asked. Do not `cargo check --target aarch64-linux-android`.

1. `flutter analyze lib/src`
2. Pick tests from `.ai/test-matrix.md` (pure vs FFI).
3. If FFI tests: `cargo build --manifest-path rust/Cargo.toml` first.
4. If `rust/src/api/` FFI surface changed: `flutter_rust_bridge_codegen generate`
   and `cargo build --release --manifest-path rust/Cargo.toml` (desktop
   `flutter run` loads `rust/target/release/`, not debug).
5. Format edits: `cargo test --lib session_format`.
