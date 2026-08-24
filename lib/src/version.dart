/// Build-time version injected via `--dart-define=APP_VERSION=<version>` in CI.
/// Falls back to a dev placeholder when not set.
const String appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');