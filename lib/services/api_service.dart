import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class ApiService {
  // Single source of truth — server URL lives in AppConfig (edit there per client).
  static const String _defaultBaseUrl = AppConfig.origin;
  static const Duration _timeout = Duration(seconds: 15);

  /// Public base URL (scheme + host) for callers like BrandingService.
  static String get baseUrl => _defaultBaseUrl;

  /// Driver Login
  static Future<Map<String, dynamic>> login(
    String schoolEmail,
    String vehicleNumber,
    String password,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$_defaultBaseUrl/api/v1/driver/login'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'school_email': schoolEmail,
          'vehicle_number': vehicleNumber,
          'password': password,
        }),
      ).timeout(_timeout);

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        // Save login data locally
        final prefs = await SharedPreferences.getInstance();
        final data = responseData['data'];
        await prefs.setString('api_token', data['api_token'] ?? '');
        await prefs.setString('driver_name', data['driver_name'] ?? 'Driver');
        await prefs.setString('vehicle_number', data['vehicle_number'] ?? '');
        await prefs.setString('school_name', data['school_name'] ?? '');
      }

      return responseData;
    } on http.ClientException {
      return {'status': 'error', 'message': 'Could not connect to server. Please check your internet connection.'};
    } catch (e) {
      return {'status': 'error', 'message': 'Connection failed: ${e.toString()}'};
    }
  }

  /// Returns true when the backend runs in demo mode. Defaults to false on any
  /// error so real deployments never show the demo button.
  static Future<bool> checkDemoMode() async {
    try {
      final response = await http.get(
        Uri.parse('$_defaultBaseUrl/api/v1/demo/config'),
        headers: {'Accept': 'application/json'},
      ).timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['demo_mode'] == true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// One-tap demo login: the server picks a seeded demo vehicle and returns the
  /// same payload as [login]. Persists the session identically.
  static Future<Map<String, dynamic>> demoLogin() async {
    try {
      final response = await http.post(
        Uri.parse('$_defaultBaseUrl/api/v1/driver/demo-login'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      ).timeout(_timeout);

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        final prefs = await SharedPreferences.getInstance();
        final data = responseData['data'];
        await prefs.setString('api_token', data['api_token'] ?? '');
        await prefs.setString('driver_name', data['driver_name'] ?? 'Driver');
        await prefs.setString('vehicle_number', data['vehicle_number'] ?? '');
        await prefs.setString('school_name', data['school_name'] ?? '');
      }

      return responseData;
    } on http.ClientException {
      return {'status': 'error', 'message': 'Could not connect to server. Please check your internet connection.'};
    } catch (e) {
      return {'status': 'error', 'message': 'Connection failed: ${e.toString()}'};
    }
  }

  /// Toggle Trip (start / stop)
  static Future<Map<String, dynamic>> toggleTrip(String apiToken, String status) async {
    try {
      final response = await http.post(
        Uri.parse('$_defaultBaseUrl/api/v1/driver/trip-status'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'api_token': apiToken,
          'status': status,
        }),
      ).timeout(_timeout);

      return jsonDecode(response.body);
    } on http.ClientException {
      return {'status': 'error', 'message': 'Could not connect to server.'};
    } catch (e) {
      return {'status': 'error', 'message': 'Connection failed: ${e.toString()}'};
    }
  }

  /// Send Location — called by the background service
  static Future<bool> sendLocation(double lat, double lng, double speed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('api_token');

      if (token == null || token.isEmpty) return false;

      final response = await http.post(
        Uri.parse('$_defaultBaseUrl/api/v1/driver/location'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'api_token': token,
          'lat': lat,
          'lng': lng,
          'speed': speed,
        }),
      ).timeout(_timeout);

      final data = jsonDecode(response.body);
      if (data['status'] != 'success') {
        print('[TRACKER] Server returned non-success: ${response.body} (Status: ${response.statusCode})');
      }
      return data['status'] == 'success';
    } catch (e) {
      print('ApiService.sendLocation error: $e');
      return false;
    }
  }
}