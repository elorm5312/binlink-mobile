import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/network/socket_service.dart';
import '../../../core/services/fcm_service.dart';
import '../../../core/services/offline_action_queue_service.dart';
import '../../../core/config/app_flavor.dart';
import '../../../shared/models/user_model.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.unknown;
  UserModel? _user;
  bool _loading = false;
  String? _error;

  AuthStatus get status => _status;
  UserModel? get user => _user;
  bool get loading => _loading;
  String? get error => _error;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  // Lazy so constructing AuthProvider never touches Firebase before
  // Firebase.initializeApp() has run (would throw "No Firebase App").
  FirebaseAuth get _firebaseAuth => FirebaseAuth.instance;
  final _googleSignIn = GoogleSignIn();

  Future<void> initialize() async {
    try {
      final userData = await SecureStorage.getUser();
      final token = await SecureStorage.getAccessToken();
      if (userData != null && token != null) {
        _user = UserModel.fromJson(userData);
        _status = AuthStatus.authenticated;
        await SocketService.connect();
        FcmService.registerToken();
        OfflineActionQueueService.syncNow();
        // Silently re-sync the account with the backend, declaring this app's
        // role. Older/legacy accounts that were created as HOUSEHOLD stay stuck
        // and get "Access denied" on collector-only actions (e.g. GO ONLINE)
        // until their stored role is reconciled — this heals them on app open
        // with no user action. Non-blocking: the UI is already up.
        unawaited(_reconcileRole());
      } else {
        _status = AuthStatus.unauthenticated;
      }
    } catch (_) {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  // ── Email + Password ─────────────────────────────────────────

  Future<bool> loginWithEmail({
    required String email,
    required String password,
    String role = 'HOUSEHOLD',
  }) async {
    _setLoading(true);
    try {
      final cred = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final idToken = await cred.user!.getIdToken();
      return await _firebaseExchange(idToken!, role: role);
    } on FirebaseAuthException catch (e) {
      _error = _firebaseError(e);
      return false;
    } on DioException catch (e) {
      _error = _extractError(e);
      return false;
    } catch (_) {
      _error = 'An unexpected error occurred during sign-in.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> registerWithEmail({
    required String email,
    required String password,
    required String fullName,
    String? phone,
    required String role,
  }) async {
    _setLoading(true);
    try {
      final cred = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await cred.user!.updateDisplayName(fullName);
      final idToken = await cred.user!.getIdToken();
      // Pass the password so the backend stores a passwordHash — this lets the
      // same email+password work on the admin portal without a separate account.
      return await _firebaseExchange(idToken!,
          fullName: fullName, phone: phone, role: role, password: password);
    } on FirebaseAuthException catch (e) {
      _error = _firebaseError(e);
      return false;
    } on DioException catch (e) {
      _error = _extractError(e);
      return false;
    } catch (_) {
      _error = 'An unexpected error occurred during registration.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ── Google Sign-In ───────────────────────────────────────────

  Future<bool> loginWithGoogle({String role = 'HOUSEHOLD'}) async {
    _setLoading(true);
    _error = null;
    try {
      // Sign out first to force account picker every time
      await _googleSignIn.signOut();
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User dismissed the picker — not an error
        _error = null;
        return false;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final cred = await _firebaseAuth.signInWithCredential(credential);
      final idToken = await cred.user!.getIdToken();
      return await _firebaseExchange(
        idToken!,
        fullName: cred.user!.displayName,
        role: role,
      );
    } on FirebaseAuthException catch (e) {
      _error = _firebaseError(e);
      return false;
    } on DioException catch (e) {
      _error = _extractError(e);
      return false;
    } on PlatformException catch (e) {
      if (e.code == '10' || e.code == 'developer_error') {
        _error =
            'Google Sign-In configuration error. Please ensure SHA-1 keys are correctly registered in Firebase for both flavors.';
      } else if (e.code == 'network_error') {
        _error =
            'Network error during Google Sign-In. Please check your connection.';
      } else {
        _error = 'Google Sign-In failed (${e.code}): ${e.message}';
      }
      return false;
    } catch (e) {
      _error = 'An unexpected error occurred during Google sign-in.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ── Password reset ───────────────────────────────────────────

  Future<bool> sendPasswordReset(String email) async {
    _setLoading(true);
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email);
      _error = null;
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _firebaseError(e);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ── Sign out ─────────────────────────────────────────────────

  Future<void> signOut() async {
    final refreshToken = await SecureStorage.getRefreshToken();
    if (refreshToken != null) {
      try {
        await ApiClient.post(
            '/api/auth/logout', {'refreshToken': refreshToken});
      } catch (_) {}
    }
    await _firebaseAuth.signOut();
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    SocketService.disconnect();
    await SecureStorage.clearAll();
    _user = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  // ── Profile helpers ──────────────────────────────────────────

  Future<void> refreshProfile() async {
    try {
      final res = await ApiClient.get('/api/profile');
      _user = UserModel.fromJson(res.data['data']);
      await SecureStorage.saveUser(_user!.toJson());
      notifyListeners();
    } catch (_) {}
  }

  void updateUser(UserModel updated) {
    _user = updated;
    SecureStorage.saveUser(updated.toJson());
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ── Private helpers ──────────────────────────────────────────

  /// Re-exchanges the still-valid Firebase session with the backend, declaring
  /// this app's role, so a legacy account created with the wrong role is healed
  /// server-side. Best-effort: any failure (offline, no Firebase session) is
  /// swallowed so it never blocks or breaks an already-authenticated session.
  Future<void> _reconcileRole() async {
    try {
      final fbUser = _firebaseAuth.currentUser;
      if (fbUser == null) return;
      // Already the right role? Nothing to do.
      if (_user?.role == FlavorConfig.defaultRole) return;
      final idToken = await fbUser.getIdToken();
      if (idToken == null) return;
      await _firebaseExchange(idToken, role: FlavorConfig.defaultRole);
    } catch (_) {
      // Ignore — the account still works for shared actions; collector-only
      // actions will prompt again next launch.
    }
  }

  Future<bool> _firebaseExchange(
    String idToken, {
    String? fullName,
    String? phone,
    String role = 'HOUSEHOLD',
    String? password,
  }) async {
    // Timeboxed: on phones without Google services (many Huaweis) getToken can
    // hang indefinitely, which stalled login before the exchange ever ran.
    final fcmToken = await FirebaseMessaging.instance
        .getToken()
        .timeout(const Duration(seconds: 5))
        .catchError((_) => null);
    final body = <String, dynamic>{
      'firebaseToken': idToken,
      'role': role,
      if (fcmToken != null) 'fcmToken': fcmToken,
    };
    if (fullName != null) body['fullName'] = fullName;
    if (phone != null) body['phone'] = phone;
    if (password != null) body['password'] = password;
    // Firebase sign-in just succeeded, so the internet is up — one automatic
    // retry absorbs transient drops to our backend instead of failing login.
    Response res;
    try {
      res = await ApiClient.post('/api/auth/firebase', body);
    } on DioException catch (e) {
      if (e.response != null) rethrow; // real server reply — don't retry
      res = await ApiClient.post('/api/auth/firebase', body);
    }
    await _handleAuthResponse(res.data['data']);
    return true;
  }

  Future<void> _handleAuthResponse(Map<String, dynamic>? data) async {
    if (data == null) throw Exception('Invalid authentication response');
    await SecureStorage.saveTokens(
      accessToken: data['accessToken'],
      refreshToken: data['refreshToken'],
    );
    final userData = data['user'];
    if (userData != null) {
      final userMap = Map<String, dynamic>.from(userData as Map);
      _user = UserModel.fromJson(userMap);
      await SecureStorage.saveUser(userMap);
    }
    _status = AuthStatus.authenticated;
    _error = null;
    await SocketService.connect();
    FcmService.registerToken();
    OfflineActionQueueService.syncNow();
    notifyListeners();
  }

  void _setLoading(bool val) {
    _loading = val;
    notifyListeners();
  }

  String _firebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'email-already-in-use':
        return 'An account already exists for this email.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with a different sign-in method.';
      default:
        return e.message ?? 'Authentication failed.';
    }
  }

  String _extractError(DioException e) {
    // A JSON error from the backend is the most specific — use it when present.
    final data = e.response?.data;
    if (data is Map && data['error'] is String) return data['error'] as String;
    // No usable response — say WHAT failed instead of a generic shrug, so
    // support/debugging can tell timeouts from unreachable servers.
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
        return 'Could not reach the server — connection timed out. Check your internet and try again.';
      case DioExceptionType.receiveTimeout:
        return 'The server took too long to respond. Please try again.';
      case DioExceptionType.connectionError:
        return 'No connection to the server. Check your internet (mobile data or Wi-Fi) and try again.';
      case DioExceptionType.badCertificate:
        return 'Secure connection failed. Check your phone\'s date & time settings.';
      default:
        final code = e.response?.statusCode;
        return code != null
            ? 'Server error ($code). Please try again shortly.'
            : 'Something went wrong. Please try again.';
    }
  }
}
