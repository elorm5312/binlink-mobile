import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/json_num.dart';

/// Keeps a "Make payment now" notification on the household's phone while a
/// completed pickup is unpaid. On Android it is an ongoing notification (cannot
/// be swiped away and stays after the app is closed) and is removed as soon as
/// nothing is owed. iOS has no persistent notifications, so it is shown once
/// per booking; the backend's payment reminders cover the rest.
class PaymentDueNotifier {
  PaymentDueNotifier._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static const _id = 7101;
  static final Set<String> _shownOnIos = {};

  static const _channel = AndroidNotificationDetails(
    'payment_due',
    'Payments due',
    channelDescription: 'Reminds you to pay for a completed pickup',
    importance: Importance.high,
    priority: Priority.high,
    ongoing: true,
    autoCancel: false,
    onlyAlertOnce: true,
    category: AndroidNotificationCategory.reminder,
  );

  static Future<void> init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Permission is requested by the push setup; don't prompt twice.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ));
      _ready = true;
    } catch (e) {
      debugPrint('[PaymentDue] init failed: $e');
    }
  }

  /// [unpaid] = completed-but-unpaid bookings, newest first.
  static Future<void> sync(List<Map<String, dynamic>> unpaid) async {
    await init();
    if (!_ready) return;
    try {
      if (unpaid.isEmpty) {
        await _plugin.cancel(_id);
        return;
      }
      final b = unpaid.first;
      final id = '${b['id']}';
      final amount = jsonDouble(b['totalAmount']) ?? 0;
      final title = 'Make payment now · GHS ${amount.toStringAsFixed(2)}';
      final body = unpaid.length == 1
          ? 'Your pickup is complete. Open BinLink Eco and tap "Make payment".'
          : 'You have ${unpaid.length} completed pickups to pay for. Open BinLink Eco.';
      final isIos = defaultTargetPlatform == TargetPlatform.iOS;
      if (isIos && _shownOnIos.contains(id)) return;
      await _plugin.show(
        _id,
        title,
        body,
        const NotificationDetails(android: _channel, iOS: DarwinNotificationDetails()),
        payload: id,
      );
      if (isIos) _shownOnIos.add(id);
    } catch (e) {
      debugPrint('[PaymentDue] sync failed: $e');
    }
  }

  static Future<void> clear() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(_id);
    } catch (_) {}
  }
}
