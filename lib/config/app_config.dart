/// SINGLE SOURCE OF TRUTH for per-client values in the driver app.
///
/// When building an APK for a new client, edit ONLY this file (server URL + the
/// display text below), or override at build time with --dart-define, e.g.:
///   flutter build apk --dart-define=API_ORIGIN=https://yourschool.com \
///                      --dart-define=APP_NAME="Heritage Driver"
///
/// NOTE: when dynamic branding is ON, the live app name comes from the backend;
/// the values below are the offline/default fallbacks.
class AppConfig {
  /// Backend server origin (scheme + host).
  static const String origin = String.fromEnvironment(
    'API_ORIGIN',
    defaultValue: 'https://multischoolv2.projectworlds.com',
  );

  // ── App display text ───────────────────────────────────────────────────────
  /// Brand / app name — splash headline, branding fallback, app bar.
  static const String appName = String.fromEnvironment(
    'APP_NAME',
    defaultValue: 'Driver Tracker',
  );

  /// "Powered by" footer text.
  static const String poweredBy = String.fromEnvironment(
    'APP_POWERED_BY',
    defaultValue: 'Powered by Projectworlds',
  );

  /// Version label shown on the about/profile area.
  static const String appVersionLabel = String.fromEnvironment(
    'APP_VERSION_LABEL',
    defaultValue: 'Driver Tracker v1.0',
  );
}
