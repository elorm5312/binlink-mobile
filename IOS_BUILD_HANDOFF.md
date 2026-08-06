# BinLink Eco — iOS Build Handoff

This is the Flutter source for the BinLink Eco mobile app. It contains **two apps
built from one codebase** (Flutter flavors): **Household** and **Collector**.
Android is fully built and shipping; **iOS has not been configured yet** — this
doc lists exactly what's here and what you need to set up to build the iOS version.

---

## 1. Project facts

| Thing | Value |
|---|---|
| Framework | Flutter (Dart SDK `>=3.3.0 <4.0.0`) — built with Flutter **3.38.1** |
| App version | `2.1.3+6` (see `pubspec.yaml`) |
| Entry points | `lib/main_household.dart`, `lib/main_collector.dart` |
| Android bundle IDs | `com.binlink.eco` (household), `com.binlink.collector` (collector) |
| Backend API | `https://binlink-backend-production.up.railway.app` (live; see `.env`) |
| Firebase project | `binlink-bd0df` |
| Supabase | `nheshfhubjjokjcaczbp` (used for chat + pickup photos) |

The backend is already deployed and running — you do **not** need to run it to
build the app. The app talks to it over HTTPS using the values in `.env`.

---

## 2. What you get to build iOS (a Mac + Xcode is required)

- `lib/` — all Dart app code (shared by both flavors)
- `ios/` — the iOS Runner project (currently the default single-target scaffold)
- `assets/`, `pubspec.yaml`, `pubspec.lock` — assets + pinned dependencies
- `.env` — runtime config (API URL, Supabase keys). Loaded via flutter_dotenv.
- `android/` — reference for how flavors, bundle IDs and Firebase are wired

Firebase/native plugins in use (all need iOS config): `firebase_core`,
`firebase_auth`, `firebase_messaging`, `firebase_crashlytics`, `google_sign_in`,
`supabase_flutter`.

---

## 3. What you MUST set up for iOS (not done yet)

### a) Firebase iOS config — REQUIRED
There is **no `GoogleService-Info.plist`** in the repo (Android has its
`google-services.json`, but iOS needs its own file). Without it, login (Firebase
Auth), Google Sign-In, push (FCM) and Crashlytics will not work.

1. In the Firebase console → project **`binlink-bd0df`** → add **two iOS apps**,
   one per flavor, using the bundle IDs you choose (recommend matching Android):
   - `com.binlink.eco` (Household)
   - `com.binlink.collector` (Collector)
2. Download each **`GoogleService-Info.plist`** and place it under the matching
   iOS build configuration/target (see flavors below). Do not commit them to a
   public repo.

### b) iOS flavors / schemes — REQUIRED
The `ios/` project is still the default single target with bundle ID
`com.binlink.binlinkMobile`. You need to reproduce the two Android flavors on iOS:
- Create **Household** and **Collector** schemes/configurations (or use
  `--flavor` with matching Xcode configs), each with its own bundle ID and its
  own `GoogleService-Info.plist`.
- Build with, e.g.:
  ```
  flutter build ipa --flavor household --target lib/main_household.dart --release
  flutter build ipa --flavor collector --target lib/main_collector.dart --release
  ```

### c) Push notifications (APNs)
`firebase_messaging` on iOS needs an **APNs key** uploaded to Firebase and the
Push Notifications + Background Modes capabilities enabled in Xcode.

### d) Google Sign-In URL scheme
Add the `REVERSED_CLIENT_ID` from each `GoogleService-Info.plist` to the app's
URL types in `Info.plist` (per flavor).

### e) Signing
Use your own Apple Developer account for signing certs & provisioning profiles.
(The Android `keystore.jks` in this repo is for Android only — irrelevant to iOS.)

---

## 4. First build steps

```bash
flutter pub get
cd ios && pod install   # generates Podfile.lock / installs native pods
cd ..
# open ios/Runner.xcworkspace in Xcode to set up signing, flavors, capabilities
flutter build ipa --flavor household --target lib/main_household.dart --release
```

---

## 5. Notes / gotchas
- App min versions: Android targets API 24+. Pick an iOS deployment target of
  **iOS 13+** (Firebase SDKs require it).
- `.env` is read at runtime — keep it in the bundle (already wired via
  `flutter_dotenv`; it's listed under assets in `pubspec.yaml`).
- The two apps differ only by flavor/entry point + branding assets — there is no
  separate iOS codebase to write.

Questions on the backend/API contract: it's a Node/Express service; the mobile
`lib/core/network/api_client.dart` shows every endpoint and header the app uses
(note the `x-app-role` header + `POST /api/auth/firebase` token exchange).
