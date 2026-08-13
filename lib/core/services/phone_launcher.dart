import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the phone's native dialer pre-filled with a number so a collector can
/// call the customer (and vice-versa). Uses the `tel:` scheme via the external
/// dialer app — this never places the call automatically, it just hands off to
/// the phone app with the number ready.
class PhoneLauncher {
  PhoneLauncher._();

  /// Returns true if the dialer opened. [phone] may be null/empty (returns false).
  static Future<bool> call(String? phone) async {
    final number = _sanitize(phone);
    if (number == null) return false;
    final uri = Uri(scheme: 'tel', path: number);
    try {
      if (await canLaunchUrl(uri)) {
        return launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      // Some Android setups report canLaunch=false for tel: yet still handle it.
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[PhoneLauncher] $uri failed: $e');
      return false;
    }
  }

  /// Keeps digits and a leading '+' (Ghana numbers are stored as +233…).
  static String? _sanitize(String? phone) {
    if (phone == null) return null;
    final cleaned = phone.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty || cleaned == '+') return null;
    return cleaned;
  }
}
