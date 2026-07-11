import 'package:flutter/material.dart';

import '../config/app_config.dart';

/// Runtime branding for the driver app. The driver UI is a fixed dark navy
/// theme; the white-label surface here is the **app name** and the **accent**
/// (the teal action color). Built from the backend `/branding` payload, or from
/// [Branding.fallback] (the values the app shipped with) when offline, on first
/// launch, or when dynamic branding is disabled.
///
/// Defensive parsing: any missing/invalid field falls back, never throws (plan
/// §0 N1). Lean variant of the shared contract — driver only needs name+accent.
@immutable
class Branding {
  final bool dynamicEnabled;
  final String appName;
  final String? logoUrl;
  final Color accent;
  final Color accentDark;

  const Branding({
    required this.dynamicEnabled,
    required this.appName,
    required this.logoUrl,
    required this.accent,
    required this.accentDark,
  });

  /// Compile-time fallback — the exact teal/navy values the driver app shipped.
  const Branding.fallback()
      : dynamicEnabled = false,
        appName = AppConfig.appName,
        logoUrl = null,
        accent = const Color(0xFF00C9A7),
        accentDark = const Color(0xFF00A388);

  factory Branding.fromJson(Map<String, dynamic> json) {
    const fb = Branding.fallback();
    final colors = (json['colors'] is Map)
        ? Map<String, dynamic>.from(json['colors'] as Map)
        : const <String, dynamic>{};

    final accent = _color(colors['accent'], fb.accent);
    return Branding(
      dynamicEnabled: json['branding_dynamic_enabled'] == true,
      appName: _name(json['app_name'], fb.appName),
      logoUrl: _url(json['logo_url']),
      accent: accent,
      // Darken the accent for pressed/gradient states.
      accentDark: Color.lerp(accent, Colors.black, 0.18) ?? accent,
    );
  }

  /// When dynamic branding is OFF, the app looks exactly as it shipped (N5).
  Branding get effective => dynamicEnabled ? this : const Branding.fallback();

  // ── Defensive parsers ──────────────────────────────────────────────────────

  static String _name(dynamic v, String fb) {
    if (v is String) {
      final t = v.trim();
      if (t.isNotEmpty) return t.length > 40 ? t.substring(0, 40) : t;
    }
    return fb;
  }

  static String? _url(dynamic v) {
    if (v is String) {
      final t = v.trim();
      if (t.startsWith('http://') || t.startsWith('https://')) return t;
    }
    return null;
  }

  static Color _color(dynamic v, Color fb) {
    if (v is String) {
      final m = RegExp(r'^#?([0-9A-Fa-f]{6})$').firstMatch(v.trim());
      if (m != null) {
        return Color(int.parse('FF${m.group(1)}', radix: 16));
      }
    }
    return fb;
  }
}
