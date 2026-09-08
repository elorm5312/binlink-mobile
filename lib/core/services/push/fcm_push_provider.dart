import 'package:firebase_messaging/firebase_messaging.dart';

import 'push_provider.dart';

/// Firebase Cloud Messaging provider. Works on any device with Google Play
/// services. This is the default provider on Play devices.
class FcmPushProvider implements PushProvider {
  @override
  String get name => 'fcm';

  @override
  Future<bool> isAvailable() async {
    // If we can obtain a token, Play services / FCM are functioning. This
    // doubles as the availability probe without pulling an extra plugin.
    try {
      final token = await FirebaseMessaging.instance.getToken();
      return token != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> getToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<String> get onTokenRefresh => FirebaseMessaging.instance.onTokenRefresh;

  @override
  void listenForeground(void Function(PushMessage message) onMessage) {
    FirebaseMessaging.onMessage.listen((RemoteMessage m) {
      onMessage(PushMessage(
        title: m.notification?.title ?? m.data['title'] as String?,
        body: m.notification?.body ?? m.data['body'] as String?,
        data: m.data.map((k, v) => MapEntry(k, v?.toString() ?? '')),
      ));
    });
  }
}
