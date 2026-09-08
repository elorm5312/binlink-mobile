import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../navigation/nav_service.dart';
import '../../network/api_client.dart';
import 'fcm_push_provider.dart';
import 'push_provider.dart';

/// Single entry point for push across providers. Picks the right backend for
/// the device at runtime (FCM on Play devices; HMS on Huawei/Play-less devices
/// once the HMS provider is added), registers the token with BinLink's backend
/// tagged by provider, and forwards token rotations.
///
/// Supersedes the old FcmService: one code path, provider-agnostic, and ready
/// for Huawei without touching any caller.
class PushManager {
  PushManager._();
  static final PushManager instance = PushManager._();

  PushProvider? _active;

  /// Resolves the active provider for this device (memoized).
  Future<PushProvider?> _resolve() async {
    if (_active != null) return _active;

    // Preference order. Add HmsPushProvider() ahead of / after FCM once the
    // huawei_push dependency + agconnect-services.json are in place:
    //   final hms = HmsPushProvider();
    //   if (await hms.isAvailable()) return _active = hms;
    final candidates = <PushProvider>[FcmPushProvider()];
    for (final p in candidates) {
      if (await p.isAvailable()) return _active = p;
    }
    return null;
  }

  String get _platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  /// Call once at startup: sets up the foreground banner and token-refresh
  /// forwarding for whichever provider is active.
  Future<void> init() async {
    final provider = await _resolve();
    if (provider == null) return;

    provider.listenForeground(_showBanner);
    provider.onTokenRefresh.listen((token) => _register(token, provider.name));
  }

  /// Call after every successful login / session restore. Silent — never throws.
  Future<void> registerToken() async {
    final provider = await _resolve();
    if (provider == null) return;
    final token = await provider.getToken();
    if (token == null) return;
    await _register(token, provider.name);
  }

  Future<void> _register(String token, String provider) async {
    try {
      await ApiClient.put('/api/profile/push-token', {
        'token': token,
        'provider': provider,
        'platform': _platform,
      });
    } catch (_) {
      // best-effort; a later refresh or app launch retries
    }
  }

  /// Android does not surface a system notification for messages that arrive
  /// while the app is foregrounded — show an in-app banner to fill that gap.
  void _showBanner(PushMessage message) {
    if (message.isEmpty) return;
    final context = NavService.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    final title = message.title ?? '';
    final body = message.body ?? '';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (body.isNotEmpty) Text(body, style: const TextStyle(fontSize: 13)),
          ],
        ),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
