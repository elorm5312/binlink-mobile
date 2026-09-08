/// A normalized push message, independent of the underlying provider (FCM/HMS).
class PushMessage {
  const PushMessage({this.title, this.body, this.data = const {}});

  final String? title;
  final String? body;
  final Map<String, String> data;

  bool get isEmpty => (title ?? '').isEmpty && (body ?? '').isEmpty;
}

/// Contract every push backend implements. The rest of the app talks only to
/// this interface via [PushManager], so adding Huawei (HMS) later is a matter
/// of writing one more implementation — no changes to callers.
abstract class PushProvider {
  /// Wire name sent to the backend: 'fcm' or 'hms'.
  String get name;

  /// True if this provider's mobile services are present on the device.
  Future<bool> isAvailable();

  /// Current device token, or null if unavailable.
  Future<String?> getToken();

  /// Fires whenever the provider rotates the token.
  Stream<String> get onTokenRefresh;

  /// Delivers foreground messages (app open) as normalized [PushMessage]s.
  void listenForeground(void Function(PushMessage message) onMessage);
}
