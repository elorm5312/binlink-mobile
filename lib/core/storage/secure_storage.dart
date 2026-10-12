import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorage {
  SecureStorage._();

  static const _android = AndroidOptions(
    encryptedSharedPreferences: false,
    keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
    storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
  );

  // iOS: readable after the first unlock since boot, so a backgrounded or
  // push-woken app (phone locked) can still read the session. The default
  // ("unlocked") made those reads fail and the app showed the login screen.
  static const _storage = FlutterSecureStorage(
    aOptions: _android,
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // Items written by older builds used the default iOS accessibility and are
  // not found through the new options; read them once and migrate.
  static const _legacy = FlutterSecureStorage(aOptions: _android);

  static const _kAccessToken  = 'access_token';
  static const _kRefreshToken = 'refresh_token';
  static const _kUser         = 'user_data';

  static Future<String?> _read(String key) async {
    final v = await _storage.read(key: key);
    if (v != null) return v;
    final old = await _legacy.read(key: key);
    if (old != null) {
      await _storage.write(key: key, value: old);
      await _legacy.delete(key: key);
    }
    return old;
  }

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: _kAccessToken,  value: accessToken),
      _storage.write(key: _kRefreshToken, value: refreshToken),
    ]);
  }

  static Future<String?> getAccessToken()  => _read(_kAccessToken);
  static Future<String?> getRefreshToken() => _read(_kRefreshToken);

  static Future<void> saveUser(Map<String, dynamic> user) =>
      _storage.write(key: _kUser, value: jsonEncode(user));

  static Future<Map<String, dynamic>?> getUser() async {
    try {
      final raw = await _read(_kUser);
      if (raw == null) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearAll() async {
    await _storage.deleteAll();
    await _legacy.deleteAll();
  }
}
