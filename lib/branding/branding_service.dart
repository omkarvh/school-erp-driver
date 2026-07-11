import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import 'branding.dart';

/// Loads white-label branding for the driver app. No Riverpod here — plain
/// static helpers over `http` + `SharedPreferences`. Every method is total and
/// degrades to the cached value / compile-time fallback (plan §5.1).
class BrandingService {
  static const String _key = 'branding_payload';
  static const Duration _timeout = Duration(seconds: 10);

  /// Read the cached branding for instant, offline bootstrap.
  static Future<Branding> loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return Branding.fromJson(Map<String, dynamic>.from(decoded));
        }
      }
    } catch (_) {
      // Corrupt cache → fallback.
    }
    return const Branding.fallback();
  }

  /// Fetch the platform brand and cache the raw payload. On any failure returns
  /// the cached/fallback brand — never throws.
  static Future<Branding> fetchAndCache() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/v1/branding'),
        headers: {'Accept': 'application/json'},
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_key, response.body);
          return Branding.fromJson(Map<String, dynamic>.from(decoded));
        }
      }
    } catch (_) {
      // Network/parse failure → keep whatever is cached.
    }
    return loadCached();
  }
}
