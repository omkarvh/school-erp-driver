import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  //static const String _defaultBaseUrl = "http://10.0.2.2:8000";
  static const String _defaultBaseUrl = "https://multischoolv2.projectworlds.com";
  static const Duration _timeout = Duration(seconds: 15);

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