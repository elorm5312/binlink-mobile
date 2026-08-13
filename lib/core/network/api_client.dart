import 'package:dio/dio.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../config/app_flavor.dart';
import '../config/env.dart';
import '../storage/secure_storage.dart';
import '../navigation/nav_service.dart';
import '../services/offline_action_queue_service.dart';

class ApiClient {
  ApiClient._();

  static Dio? _instance;

  static Dio get instance {
    _instance ??= _build();
    return _instance!;
  }

  // Per-request timeout overrides — pass via Options(extra: {...})
  // Default timeouts tuned for Ghana 3G: fast connect, generous receive
  // 20s: TLS to the EU-hosted backend over congested 3G regularly exceeds 10s,
  // which surfaced as "Something went wrong" on login for real users.
  static const _connectTimeout = Duration(seconds: 20);
  static const _receiveTimeout =
      Duration(seconds: 30); // longer for list endpoints on slow networks

  static Dio _build() {
    final dio = Dio(BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: _connectTimeout,
      receiveTimeout: _receiveTimeout,
      headers: {
        'Content-Type': 'application/json',
        // Declares which flavor this app is on every request so the backend
        // can heal the account's role instantly if it got flipped by the
        // other app (one account used in both apps → 403 Access denied).
        'x-app-role': FlavorConfig.defaultRole,
      },
    ));

    dio.interceptors.add(_AuthInterceptor(dio));
    return dio;
  }

  // Auth helpers
  static Future<Response> post(String path, Map<String, dynamic> data) =>
      instance.post(path, data: data);

  /// Multipart file upload — uses a longer receive timeout (60s) for photo uploads on Ghana 3G.
  static Future<Response> upload(String path, FormData formData) =>
      instance.post(
        path,
        data: formData,
        options: Options(
          receiveTimeout: const Duration(seconds: 60),
          contentType: 'multipart/form-data',
        ),
      );

  static Future<Response<dynamic>> send(
    String method,
    String path, {
    dynamic data,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
  }) {
    return instance.request(
      path,
      data: data,
      options: Options(
        method: method,
        headers: headers,
        extra: extra,
      ),
    );
  }

  static Future<Response> get(String path, {Map<String, dynamic>? params}) =>
      instance.get(path, queryParameters: params);

  static Future<Response> put(String path, [Map<String, dynamic>? data]) =>
      instance.put(path, data: data);

  static Future<Response> patch(String path, [Map<String, dynamic>? data]) =>
      instance.patch(path, data: data);

  static Future<Response> delete(String path) => instance.delete(path);

  /// Best-effort human-readable message from a caught request error.
  /// Prefers the backend's `error`/`message` field, falls back to null.
  static String? messageFrom(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final msg = data['error'] ?? data['message'];
        if (msg is String && msg.isNotEmpty) return msg;
      }
    }
    return null;
  }
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._dio);
  final Dio _dio;
  bool _isRefreshing = false;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Only add token if not already present or explicitly cleared
    if (!options.headers.containsKey('Authorization')) {
      final token = await SecureStorage.getAccessToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    if (_needsIdempotency(options)) {
      final idempKey = await _buildIdempotencyKey(options);
      options.headers.putIfAbsent('Idempotency-Key', () => idempKey);
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    try {
      await FirebaseCrashlytics.instance.recordError(
        err,
        err.stackTrace,
        reason: 'API request failed',
        information: [
          'method=${err.requestOptions.method}',
          'path=${err.requestOptions.path}',
          'status=${err.response?.statusCode}',
        ],
      );
    } catch (_) {}

    if (_isOfflineFailure(err) &&
        OfflineActionQueueService.shouldQueue(err.requestOptions)) {
      await OfflineActionQueueService.enqueue(err.requestOptions);
      handler.resolve(
        Response(
          requestOptions: err.requestOptions,
          statusCode: 202,
          data: const {
            'success': true,
            'queued': true,
            'offline': true,
          },
        ),
      );
      return;
    }

    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;
      try {
        final refreshToken = await SecureStorage.getRefreshToken();
        if (refreshToken == null) {
          await SecureStorage.clearAll();
          NavService.pushNamedAndRemoveUntil('/login');
          handler.next(err);
          return;
        }

        final res = await _dio.post(
          '/api/auth/refresh',
          data: {'refreshToken': refreshToken},
          options: Options(headers: {'Authorization': ''}),
        );

        final data = res.data['data'];
        await SecureStorage.saveTokens(
          accessToken: data['accessToken'],
          refreshToken: data['refreshToken'],
        );
        await SecureStorage.saveUser(Map<String, dynamic>.from(data['user']));

        // Retry original request
        final opts = err.requestOptions;
        opts.headers['Authorization'] = 'Bearer ${data['accessToken']}';
        final retried = await _dio.fetch(opts);
        handler.resolve(retried);
      } catch (refreshErr) {
        // Only destroy the session when the refresh token is genuinely rejected
        // by the server (401/403). A transient network failure during refresh
        // (very common on Ghana 3G) must NOT log the user out — that was causing
        // spurious auto-logouts. In that case keep the session and just surface
        // the original error so the user can retry, still signed in.
        final rejected = refreshErr is DioException &&
            (refreshErr.response?.statusCode == 401 ||
                refreshErr.response?.statusCode == 403);
        if (rejected) {
          await SecureStorage.clearAll();
          NavService.pushNamedAndRemoveUntil('/login');
        }
        handler.next(err);
      } finally {
        _isRefreshing = false;
      }
    } else {
      handler.next(err);
    }
  }

  bool _needsIdempotency(RequestOptions options) {
    if (options.method.toUpperCase() != 'POST') return false;
    final path = options.path;
    return path == '/api/bookings' ||
        path == '/api/payments/initialize' ||
        path == '/api/payments/verify' ||
        path == '/api/payments/wallet/top-up/initialize' ||
        path == '/api/payments/wallet/top-up/verify' ||
        path.contains('/review') ||
        path.contains('/rating') ||
        path == '/api/support/tickets';
  }

  Future<String> _buildIdempotencyKey(RequestOptions options) async {
    final user = await SecureStorage.getUser();
    final userId = user?['id'] as String? ?? 'anon';
    final payload = _stableStringify(options.data);
    final seed = '$userId:${options.method}:${options.path}:$payload';
    return seed.hashCode.toUnsigned(32).toRadixString(16);
  }

  String _stableStringify(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return '{${keys.map((key) => '"$key":${_stableStringify(value[key])}').join(',')}}';
    }
    if (value is List) {
      return '[${value.map(_stableStringify).join(',')}]';
    }
    if (value == null) return 'null';
    if (value is String) return '"$value"';
    return value.toString();
  }

  bool _isOfflineFailure(DioException err) {
    return err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        (err.error?.toString().toLowerCase().contains('socket') ?? false);
  }
}
