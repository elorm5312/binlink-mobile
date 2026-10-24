import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Rings/wakes the screen for incoming calls and new pickup requests even when
/// the app is backgrounded or the phone is asleep.
///
/// - Calls use a full-screen-intent notification (max importance) so the ring
///   shows over the Android lock screen — a plain push can't do that.
/// - New jobs use a high-importance heads-up notification with sound so a
///   collector whose screen is off still hears/sees the request.
///
/// Android-only behaviour. iOS keeps the standard push (true background call UI
/// on iOS needs CallKit + VoIP push, which is a later addition).
class CallWake {
  CallWake._();
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const callChannel = 'binlink_calls';
  static const jobChannel = 'binlink_jobs';
  static const _callId = 7201;
  static const _jobId = 7202;

  static Future<void> ensureInit() async {
    if (_ready) return;
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ));
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(const AndroidNotificationChannel(
        callChannel, 'Incoming calls',
        description: 'Rings for incoming in-app calls',
        importance: Importance.max,
        playSound: true,
      ));
      await android.createNotificationChannel(const AndroidNotificationChannel(
        jobChannel, 'New pickup requests',
        description: 'Alerts you to new pickup requests',
        importance: Importance.high,
        playSound: true,
      ));
      try { await android.requestNotificationsPermission(); } catch (_) {}
      // Android 14+: needed for the call notification to appear full-screen on
      // the lock screen. Best-effort — ignored where the API isn't present.
      try { await android.requestFullScreenIntentPermission(); } catch (_) {}
    }
    _ready = true;
  }

  static Future<void> showIncomingCall({required String title, required String body}) async {
    await ensureInit();
    await _plugin.show(
      _callId,
      title.isEmpty ? 'Incoming call' : title,
      body.isEmpty ? 'Tap to answer' : body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          callChannel, 'Incoming calls',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: false,
          visibility: NotificationVisibility.public,
        ),
      ),
    );
  }

  static Future<void> clearCall() async {
    try { await _plugin.cancel(_callId); } catch (_) {}
  }

  static Future<void> showJob({required String title, required String body}) async {
    await ensureInit();
    await _plugin.show(
      _jobId,
      title.isEmpty ? 'New pickup request' : title,
      body.isEmpty ? 'Tap to view the request' : body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          jobChannel, 'New pickup requests',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
          visibility: NotificationVisibility.public,
        ),
      ),
    );
  }
}

/// FCM background-isolate handler. Registered in the app entrypoints via
/// FirebaseMessaging.onBackgroundMessage. Turns a CALL / booking:new data push
/// into a ringing full-screen / heads-up notification while the app is asleep.
@pragma('vm:entry-point')
Future<void> binlinkFcmBackground(RemoteMessage message) async {
  try {
    final data = message.data;
    final type = (data['type'] ?? '').toString();
    final title = (data['title'] ?? message.notification?.title ?? '').toString();
    final body = (data['body'] ?? message.notification?.body ?? '').toString();
    if (type == 'CALL') {
      await CallWake.showIncomingCall(title: title, body: body);
    } else if (type == 'booking:new') {
      await CallWake.showJob(title: title, body: body);
    }
  } catch (_) {}
}
