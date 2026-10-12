import 'package:firebase_core/firebase_core.dart';

import 'app_flavor.dart';

/// iOS Firebase apps registered in project binlink-bd0df. Both flavors share
/// one Xcode target (bundle ID is set per app at build time), so the config is
/// chosen in Dart instead of bundling a GoogleService-Info.plist.
class FirebaseIosOptions {
  static const _shared = (
    apiKey: 'AIzaSyD-CCJITuvX4O9Qo1C7sPujbL176Ohk0Ys',
    messagingSenderId: '781294511680',
    projectId: 'binlink-bd0df',
    storageBucket: 'binlink-bd0df.firebasestorage.app',
  );

  static const householdClientId =
      '781294511680-ar4r2v03fhhltcantq21gk4nh1ce8ins.apps.googleusercontent.com';
  static const collectorClientId =
      '781294511680-2937hgimu0d47hg4j54fk3khi0rqhbma.apps.googleusercontent.com';

  static String get clientId =>
      FlavorConfig.isCollector ? collectorClientId : householdClientId;

  static FirebaseOptions forFlavor(AppFlavor flavor) {
    final collector = flavor == AppFlavor.collector;
    return FirebaseOptions(
      apiKey: _shared.apiKey,
      appId: collector
          ? '1:781294511680:ios:6631575c259884c93321a5'
          : '1:781294511680:ios:a92ec3c42b2718a43321a5',
      messagingSenderId: _shared.messagingSenderId,
      projectId: _shared.projectId,
      storageBucket: _shared.storageBucket,
      iosClientId: collector ? collectorClientId : householdClientId,
      iosBundleId: collector ? 'com.binlink.collector' : 'com.binlink.eco',
    );
  }
}
