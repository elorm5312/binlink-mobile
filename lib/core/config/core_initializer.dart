import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show MapLibreMap;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_flavor.dart';
import 'env.dart';
import '../design_system/collector_design_system.dart';
import '../services/background_location_service.dart';
import '../services/fcm_service.dart';
import '../services/offline_action_queue_service.dart';
import '../network/api_client.dart';

class CoreInitializer {
  /// Runs the minimum needed to paint the first frame, then kicks off the
  /// heavy services (Firebase, FCM permission prompt, offline queue) in the
  /// BACKGROUND. Previously everything was awaited serially before runApp —
  /// including a notification-permission dialog — so the app showed a blank
  /// screen for several seconds on slow networks.
  static Future<void> init(AppFlavor flavor) async {
    WidgetsFlutterBinding.ensureInitialized();
    FlavorConfig.flavor = flavor;

    // MapLibre default (virtual display) hosts the map in a SurfaceView,
    // which Flutter virtual displays do NOT support — covering the map with
    // a sheet or moving it offstage (IndexedStack tab switch) crashes the
    // process natively on many devices. Hybrid composition makes maplibre
    // 0.26.1 render via TextureView instead, which survives both.
    MapLibreMap.useHybridComposition = true;

    // 1. Environment variables — needed before the first API/Supabase call,
    //    but it's a local asset read so it's fast.
    try {
      await dotenv.load(fileName: '.env');
    } catch (e) {
      debugPrint('[Core] .env load failed: $e. Falling back to defaults.');
    }

    // 2. Supabase — init is local setup (no network round-trip), and chat/photo
    //    screens need it, so keep it on the critical path. Cheap.
    try {
      if (Env.supabaseUrl.isNotEmpty) {
        await Supabase.initialize(
          url: Env.supabaseUrl,
          publishableKey: Env.supabaseAnonKey,
        );
      }
    } catch (e) {
      debugPrint('[Core] Supabase init failed: $e');
    }

    // 3. Orientation + system chrome — cheap, and avoids a first-frame flash.
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    final isCollector = flavor == AppFlavor.collector;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isCollector ? Brightness.light : Brightness.dark,
      systemNavigationBarColor:
          isCollector ? CollectorColors.dark : Colors.white,
      systemNavigationBarIconBrightness:
          isCollector ? Brightness.light : Brightness.dark,
    ));

    // Everything below is non-blocking: the UI renders now, these finish in the
    // background within the first second or two.
    unawaited(_initBackgroundServices(flavor));
  }

  static Future<void> _initBackgroundServices(AppFlavor flavor) async {
    // Firebase & Crashlytics
    try {
      await Firebase.initializeApp();

      // Route Flutter framework errors to Crashlytics
      // recordFlutterError (non-fatal) — NOT recordFlutterFatalError which kills the app
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        FirebaseCrashlytics.instance.recordFlutterError(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };

      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);

      // Notifications — this can pop a system permission dialog, which is fine
      // now that the UI is already visible behind it.
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      FcmService.listenForRefresh();
      FcmService.listenForeground();
    } catch (e) {
      debugPrint('[Core] Firebase init failed: $e');
      FlutterError.onError = FlutterError.presentError;
    }

    // Background location service — collector flavor only
    if (flavor == AppFlavor.collector) {
      BackgroundLocationService.init();
    }

    try {
      await OfflineActionQueueService.init(
        dispatcher: (method, path, data, headers) => ApiClient.send(
          method,
          path,
          data: data,
          headers: headers,
          extra: const {'skipOfflineQueue': true},
        ),
      );
    } catch (e) {
      debugPrint('[Core] Offline queue init failed: $e');
    }
  }

  static void handleError(Object error, StackTrace stack) {
    debugPrint('[Fatal Error] $error\n$stack');
    try {
      // Only attempt Crashlytics if initialized
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    } catch (_) {
      // If Crashlytics itself throws, we just print and let the app die
      debugPrint('[Fatal Error] Could not report to Crashlytics');
    }
  }
}
