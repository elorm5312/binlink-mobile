import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

class LocationService {
  LocationService._();

  static Future<bool> requestPermission() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  static Future<Position?> getLastKnownPosition() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  static Future<Position?> getCurrentPosition() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return null;

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 30),
      );
    } catch (_) {
      return null;
    }
  }

  /// [background] starts an Android location foreground service, which only
  /// the collector flavor declares in its manifest.
  static Stream<Position> getPositionStream({bool background = false}) {
    final settings = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
          intervalDuration: const Duration(seconds: 30),
          foregroundNotificationConfig: background
              ? const ForegroundNotificationConfig(
                  notificationTitle: 'BinLink Collector tracking active',
                  notificationText:
                      'Live route tracking is running in the background.',
                  enableWakeLock: true,
                )
              : null,
        ),
      TargetPlatform.iOS || TargetPlatform.macOS => AppleSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
        ),
      _ => const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
    };
    return Geolocator.getPositionStream(
      locationSettings: settings,
    );
  }

  static double distanceMeters(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    return Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
  }

  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
}
