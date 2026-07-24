import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Launches external Google Maps turn-by-turn navigation to a coordinate.
///
/// Collectors use Google Maps (not the in-app map) for real driving accuracy.
/// The `google.navigation:` intent opens Maps already in navigation mode and
/// auto-starts the trip; we fall back to the universal Maps URL, then a plain
/// geo: URI, so it still works if Google Maps isn't installed.
class MapsLauncher {
  MapsLauncher._();

  static Future<bool> navigateTo(double lat, double lng, {String? label}) async {
    final candidates = <Uri>[
      // Android: opens Google Maps directly in driving-navigation mode.
      Uri.parse('google.navigation:q=$lat,$lng&mode=d'),
      // Universal Maps directions link with navigation requested.
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving&dir_action=navigate',
      ),
      // Last resort: drop a pin (any map app).
      Uri.parse('geo:$lat,$lng?q=$lat,$lng${label != null ? '(${Uri.encodeComponent(label)})' : ''}'),
    ];

    for (final uri in candidates) {
      try {
        if (await canLaunchUrl(uri)) {
          final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (ok) return true;
        }
      } catch (e) {
        debugPrint('[MapsLauncher] $uri failed: $e');
      }
    }
    return false;
  }
}
