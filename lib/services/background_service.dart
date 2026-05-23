import 'dart:async';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

import 'api_service.dart';

// ─── Initialize the Background Service ──────────────────────────
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'vehicle_tracking',
    'Vehicle Tracking',
    description: 'Shows when vehicle location is being tracked.',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flnp =
      FlutterLocalNotificationsPlugin();

  await flnp
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      autoStartOnBoot: true,
      notificationChannelId: 'vehicle_tracking',
      initialNotificationTitle: 'School Bus Tracker',
      initialNotificationContent: 'Starting tracking...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

// ─── iOS Background Handler ────────────────────────────────────
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  try {
    DartPluginRegistrant.ensureInitialized();
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
      timeLimit: const Duration(seconds: 15),
    );
    await ApiService.sendLocation(
        position.latitude, position.longitude, position.speed);
  } catch (e) {
    print('[TRACKER] iOS bg error: $e');
  }
  return true;
}

// ─── Main Background Service Entry Point ────────────────────────
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  print('[TRACKER] === SERVICE STARTED ===');

  // Track subscriptions/timers for clean teardown
  StreamSubscription<Position>? positionSubscription;
  Timer? heartbeatTimer;
  Timer? retryTimer;

  // Track state for de-duplication and retry
  int consecutiveFailures = 0;
  DateTime? lastSentTime;
  double? lastLat;
  double? lastLng;

  service.on('stopService').listen((event) {
    print('[TRACKER] === SERVICE STOPPING ===');
    positionSubscription?.cancel();
    heartbeatTimer?.cancel();
    retryTimer?.cancel();
    service.stopSelf();
  });

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) => service.setAsForegroundService());
    service.on('setAsBackground').listen((_) => service.setAsBackgroundService());
  }

  // ── CORE FIX: Use getPositionStream() instead of Timer.periodic ──
  //
  // WHY: Timer.periodic + getCurrentPosition() fails in background because:
  //   1. Android Doze mode suspends Dart timers
  //   2. getCurrentPosition() opens a new GPS session each call (cold-start = slow)
  //   3. Timer isolate gets killed by Android OOM killer
  //
  // getPositionStream() uses a PERSISTENT platform channel that:
  //   - Keeps GPS radio alive continuously (no cold-start delays)
  //   - Survives Doze mode because it's a foreground service location request
  //   - Streams positions via native LocationCallback (not Dart timer)
  //   - Automatically handles GPS provider changes

  final LocationSettings locationSettings = AndroidSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    // Minimum distance change (meters) before we get a callback
    // 10m prevents flooding API when the bus is stationary
    distanceFilter: 10,
    // Request interval — guaranteed minimum between updates
    intervalDuration: const Duration(seconds: 10),
    // Keep alive even in background / Doze
    foregroundNotificationConfig: const ForegroundNotificationConfig(
      notificationTitle: 'School Bus Tracker',
      notificationText: 'Tracking your route...',
      notificationChannelName: 'Vehicle Tracking',
      setOngoing: true,
      enableWakeLock: true, // ← KEY: Acquires WAKE_LOCK automatically
    ),
  );

  // Send first position immediately via one-shot (don't wait for stream)
  await _sendImmediateLocation(service);

  // Start the persistent position stream
  positionSubscription = Geolocator.getPositionStream(
    locationSettings: locationSettings,
  ).listen(
    (Position position) async {
      print('[TRACKER] Stream: ${position.latitude}, ${position.longitude} '
          '(±${position.accuracy.toInt()}m, speed: ${position.speed.toStringAsFixed(1)} m/s)');

      // Filter out cell-tower garbage fixes (>100m accuracy)
      if (position.accuracy > 100) {
        print('[TRACKER] Discarding inaccurate fix: ${position.accuracy.toInt()}m');
        _notify(service, 'Low accuracy (${position.accuracy.toInt()}m), waiting for GPS...');
        return;
      }

      // De-duplicate: skip if position hasn't meaningfully changed AND we sent recently (<8s ago)
      if (lastSentTime != null && lastLat != null && lastLng != null) {
        final elapsed = DateTime.now().difference(lastSentTime!).inSeconds;
        final distance = Geolocator.distanceBetween(
          lastLat!, lastLng!, position.latitude, position.longitude,
        );
        // If moved <3m and last sent <8s ago, skip to avoid API flooding
        if (distance < 3 && elapsed < 8) {
          return;
        }
      }

      // Send to server
      final success = await ApiService.sendLocation(
        position.latitude,
        position.longitude,
        position.speed,
      );

      final now = DateTime.now();
      final time = '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';

      if (success) {
        consecutiveFailures = 0;
        lastSentTime = now;
        lastLat = position.latitude;
        lastLng = position.longitude;
        print('[TRACKER] ✓ Sent at $time (±${position.accuracy.toInt()}m)');
        _notify(service, '✓ Sent at $time (±${position.accuracy.toInt()}m)');
      } else {
        consecutiveFailures++;
        print('[TRACKER] ✗ Failed at $time (consecutive: $consecutiveFailures)');
        _notify(service, '✗ Failed at $time, retrying...');

        // Exponential backoff retry: 2s, 4s, 8s, max 30s
        if (consecutiveFailures <= 5) {
          final delaySeconds = (2 * consecutiveFailures).clamp(2, 30);
          retryTimer?.cancel();
          retryTimer = Timer(Duration(seconds: delaySeconds), () async {
            final retryPosition = await _safeGetPosition();
            if (retryPosition != null) {
              final retrySuccess = await ApiService.sendLocation(
                retryPosition.latitude,
                retryPosition.longitude,
                retryPosition.speed,
              );
              if (retrySuccess) {
                consecutiveFailures = 0;
                lastSentTime = DateTime.now();
                lastLat = retryPosition.latitude;
                lastLng = retryPosition.longitude;
                _notify(service, '✓ Retry successful');
              }
            }
          });
        }
      }
    },
    onError: (error) {
      print('[TRACKER] Stream error: $error');
      _notify(service, 'GPS error, recovering...');
    },
    cancelOnError: false, // CRITICAL: Don't kill subscription on transient errors
  );

  // ── HEARTBEAT: Fallback timer as safety net ──────────────────────
  // If the position stream stalls (e.g., bus is stationary for 5+ min and
  // distanceFilter prevents callbacks), this timer forces a location send
  // every 60s so the server knows the device is still alive.
  heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
    final now = DateTime.now();
    if (lastSentTime != null && now.difference(lastSentTime!).inSeconds < 55) {
      return; // Stream is active, no heartbeat needed
    }

    print('[TRACKER] Heartbeat: stream idle, sending fallback position...');
    final position = await _safeGetPosition();
    if (position != null) {
      final success = await ApiService.sendLocation(
        position.latitude,
        position.longitude,
        position.speed,
      );
      if (success) {
        lastSentTime = now;
        lastLat = position.latitude;
        lastLng = position.longitude;
        _notify(service, '✓ Heartbeat at ${now.hour.toString().padLeft(2, '0')}:'
            '${now.minute.toString().padLeft(2, '0')}');
      }
    }
  });
}

/// Get position with multi-strategy fallback.
/// Returns null only if ALL strategies fail.
Future<Position?> _safeGetPosition() async {
  // Strategy 1: Best-for-navigation (GPS + GNSS + sensor fusion)
  try {
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
      timeLimit: const Duration(seconds: 15),
    );
  } catch (e) {
    print('[TRACKER] Best accuracy fallback failed: $e');
  }

  // Strategy 2: High accuracy
  try {
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 10),
    );
  } catch (e) {
    print('[TRACKER] High accuracy fallback failed: $e');
  }

  // Strategy 3: Last known position (cached from any app on device)
  try {
    final lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null) {
      print('[TRACKER] Using cached position (±${lastKnown.accuracy.toInt()}m)');
      return lastKnown;
    }
  } catch (e) {
    print('[TRACKER] Last known failed: $e');
  }

  return null;
}

/// Send location immediately at service start (don't wait for stream first tick).
Future<void> _sendImmediateLocation(ServiceInstance service) async {
  try {
    final position = await _safeGetPosition();
    if (position == null) {
      _notify(service, 'Waiting for GPS signal...');
      return;
    }

    if (position.accuracy > 100) {
      _notify(service, 'Low accuracy (${position.accuracy.toInt()}m), waiting for GPS...');
      return;
    }

    final success = await ApiService.sendLocation(
      position.latitude,
      position.longitude,
      position.speed,
    );

    final now = DateTime.now();
    final time = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';

    if (success) {
      _notify(service, '✓ Started at $time (±${position.accuracy.toInt()}m)');
    } else {
      _notify(service, '✗ Initial send failed, stream will retry...');
    }
  } catch (e) {
    print('[TRACKER] Initial location error: $e');
    _notify(service, 'Starting GPS...');
  }
}

void _notify(ServiceInstance service, String content) {
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: 'School Bus Tracker',
      content: content,
    );
  }
}