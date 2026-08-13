import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/socket_service.dart';
import '../../../core/services/background_location_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/app_notification.dart';

class CollectorProvider extends ChangeNotifier {
  final List<Map<String, dynamic>> _pendingRequests = [];
  List<Map<String, dynamic>> _activePickups   = [];
  List<Map<String, dynamic>> _completedPickups = [];
  bool _isOnline = false;
  bool _loading = false;
  String? _error;

  StreamSubscription? _locationSub;
  bool _listeningForBookings = false;

  double? _currentLat;
  double? _currentLng;
  double? _currentHeading;
  double? _currentSpeedKph;

  double? get currentLat => _currentLat;
  double? get currentLng => _currentLng;
  double? get currentHeading => _currentHeading;
  double get currentSpeedKph => _currentSpeedKph ?? 0.0;

  List<Map<String, dynamic>> get pendingRequests  => _pendingRequests;
  List<Map<String, dynamic>> get activePickups    => _activePickups;
  List<Map<String, dynamic>> get completedPickups => _completedPickups;
  bool get isOnline  => _isOnline;
  bool get loading   => _loading;
  String? get error  => _error;

  Map<String, dynamic>? get currentActivePickup =>
      _activePickups.isNotEmpty ? _activePickups.first : null;

  // Earnings helpers
  // Platform takes 10%; collector earns 90% of totalAmount
  static const _collectorRate = 0.9;
  Map<String, dynamic>? _earningsSummary;

  double get totalEarnings => Fmt.toDouble(_earningsSummary?['lifetime']?['netEarnings']);

  double get todayEarnings => _completedPickups.where((b) {
    final d = DateTime.tryParse(b['completedAt'] as String? ?? '');
    return d != null &&
        d.day == DateTime.now().day &&
        d.month == DateTime.now().month &&
        d.year == DateTime.now().year;
  }).fold(0, (s, b) => s + Fmt.toDouble(b['totalAmount']) * _collectorRate);

  int get todayPickups => _completedPickups.where((b) {
    final d = DateTime.tryParse(b['completedAt'] as String? ?? '');
    return d != null &&
        d.day == DateTime.now().day &&
        d.month == DateTime.now().month &&
        d.year == DateTime.now().year;
  }).length;

  int get totalPickups => _completedPickups.length;

  Future<void> loadEarningsSummary() async {
    try {
      final res = await ApiClient.get('/api/collectors/earnings/summary');
      _earningsSummary = Map<String, dynamic>.from(res.data['data'] as Map);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadDashboard() async {
    _setLoading(true);
    try {
      // Load this collector's assigned/completed bookings
      final res = await ApiClient.get('/api/bookings');
      final all = List<Map<String, dynamic>>.from(res.data['data'] as List);
      _completedPickups = all.where((b) => b['status'] == 'COMPLETED').toList();
      _activePickups    = all.where((b) =>
        ['ASSIGNED', 'ACCEPTED', 'EN_ROUTE', 'ON_THE_WAY',
         'ARRIVED', 'COLLECTING', 'COLLECTED'].contains(b['status'])
      ).toList();

      // Load unassigned PENDING bookings within 30 km — fills the request queue
      // even when the collector was offline when jobs were created
      final avail = await ApiClient.get('/api/bookings/available');
      final available = List<Map<String, dynamic>>.from(avail.data['data'] as List? ?? []);
      // Merge: keep existing socket-received jobs, add any new ones from API
      for (final b in available) {
        if (!_pendingRequests.any((r) => r['id'] == b['id'])) {
          _pendingRequests.add(b);
        }
      }

      _error = null;
    } on DioException catch (e) {
      _error = e.response?.data?['error'] ?? 'Failed to load dashboard';
    } finally {
      _setLoading(false);
    }
    loadEarningsSummary().catchError((_) {});
    _listenForNewBookings();
  }

  void _listenForNewBookings() {
    if (_listeningForBookings) return;
    _listeningForBookings = true;
    SocketService.on('booking:new', (data) {
      try {
        final booking = Map<String, dynamic>.from(data as Map);
        if (!_pendingRequests.any((r) => r['id'] == booking['id'])) {
          _pendingRequests.insert(0, booking);
          notifyListeners();
        }
      } catch (_) {}
    });

    SocketService.on('booking:taken', (data) {
      try {
        final id = (data as Map<String, dynamic>)['bookingId'] as String?;
        if (id != null) {
          _pendingRequests.removeWhere((r) => r['id'] == id);
          notifyListeners();
        }
      } catch (_) {}
    });

    SocketService.on('booking:completed', (data) {
      try {
        final booking = Map<String, dynamic>.from(data as Map);
        _activePickups.removeWhere((p) => p['id'] == booking['id']);
        if (!_completedPickups.any((p) => p['id'] == booking['id'])) {
          _completedPickups.insert(0, booking);
          notifyListeners();
        }
      } catch (_) {}
    });

    // Truck-full warning — backend emits at ≥90% load with the nearest dumpsite.
    SocketService.on('capacity:warning', (data) {
      try {
        _capacity = Map<String, dynamic>.from(data as Map);
        notifyListeners();
      } catch (_) {}
    });
  }

  // ── Capacity / dumpsite routing ─────────────────────────────────────────────
  Map<String, dynamic>? _capacity;
  bool get isCapacityWarning => _capacity != null;
  int get loadPercent => ((_capacity?['percentFull'] as num?) ?? 0).round();
  Map<String, dynamic>? get nearestDumpsite =>
      _capacity?['nearestDumpsite'] as Map<String, dynamic>?;

  /// Collector confirms they have offloaded at a facility. Resets the truck load
  /// on the backend and clears the local capacity warning.
  Future<bool> dumpLoad({String? facilityId}) async {
    try {
      await ApiClient.post('/api/collectors/dump-load', {
        if (facilityId != null) 'facilityId': facilityId,
      });
      _capacity = null;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  void dismissCapacityWarning() {
    _capacity = null;
    notifyListeners();
  }

  /// Re-syncs online state from the server on app start. Online is a deliberate
  /// state that survives app exits/network drops — so if the server still has
  /// the collector online, we silently re-establish the socket + location feed
  /// without re-toggling (they never pressed go-offline).
  Future<void> syncOnlineFromServer() async {
    try {
      final res = await ApiClient.get('/api/profile');
      final serverOnline = (res.data['data']?['isOnline'] as bool?) ?? false;
      if (serverOnline && !_isOnline) {
        _isOnline = true;
        SocketService.goOnline();
        _startLocationBroadcast();
        BackgroundLocationService.start();
        notifyListeners();
      } else if (!serverOnline && _isOnline) {
        _isOnline = false;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Toggles the collector's online state. Returns true on success. On failure
  /// the state is reverted and [error] holds a user-facing message so the UI
  /// can show it (a silent revert made the button look dead).
  Future<bool> toggleOnline() async {
    final newState = !_isOnline;

    // Going online requires location permission — without it we can never
    // broadcast GPS, so jobs would never reach the collector's map.
    if (newState) {
      final granted = await LocationService.requestPermission();
      if (!granted) {
        _error = 'Location permission is required to go online. Enable it in Settings.';
        notifyListeners();
        return false;
      }
    }

    _isOnline = newState;
    _error = null;
    notifyListeners();

    try {
      await ApiClient.put('/api/profile/online', {'isOnline': newState});
      if (newState) {
        SocketService.goOnline();
        _startLocationBroadcast();
        BackgroundLocationService.start();
      } else {
        SocketService.goOffline();
        _stopLocationBroadcast();
        BackgroundLocationService.stop();
        _pendingRequests.clear();
        notifyListeners();
      }
      return true;
    } catch (e) {
      _isOnline = !newState;
      _error = e is DioException
          ? (e.response?.data?['error'] ?? 'Failed to go ${newState ? 'online' : 'offline'}')
          : 'Network error — check connection';
      notifyListeners();
      return false;
    }
  }

  void _startLocationBroadcast() {
    _locationSub?.cancel();
    DateTime lastUiNotify = DateTime.fromMillisecondsSinceEpoch(0);
    _locationSub = LocationService.getPositionStream().listen((pos) async {
      _currentLat = pos.latitude;
      _currentLng = pos.longitude;
      _currentHeading = pos.heading;
      _currentSpeedKph = pos.speed * 3.6;
      // Perf: GPS can emit several samples/second. Rebuilding the whole map
      // Stack that often made the app feel sluggish. Coalesce UI notifications
      // to ~1/s (speed/ETA don't need finer granularity); socket broadcasts
      // below stay at full rate so live tracking is unaffected.
      final now = DateTime.now();
      if (now.difference(lastUiNotify).inMilliseconds >= 900) {
        lastUiNotify = now;
        notifyListeners();
      }

      // Broadcast general location for zones (always)
      SocketService.broadcastLocation(
        lat: pos.latitude,
        lng: pos.longitude,
      );

      // Targeted broadcast to active booking rooms — starts at ACCEPTED so the
      // household sees the collector approaching from the moment they accept.
      for (final pickup in _activePickups) {
        if (['ASSIGNED', 'ACCEPTED', 'EN_ROUTE', 'ON_THE_WAY', 'ARRIVED', 'COLLECTING'].contains(pickup['status'])) {
          SocketService.broadcastLocation(
            bookingId: pickup['id'] as String,
            lat: pos.latitude,
            lng: pos.longitude,
          );
        }
      }
    });
  }

  void _stopLocationBroadcast() {
    _locationSub?.cancel();
    _locationSub = null;
  }

  /// Accepts a job and returns the full accepted booking (with pickup coords +
  /// household photos), or null on failure, so the caller can jump straight
  /// into the active-pickup screen.
  Future<Map<String, dynamic>?> acceptRequest(String bookingId) async {
    try {
      final res = await ApiClient.put('/api/bookings/$bookingId/accept');
      final booking = Map<String, dynamic>.from(res.data['data'] as Map);
      _pendingRequests.removeWhere((r) => r['id'] == bookingId);
      _activePickups.add(booking);
      notifyListeners();
      return booking;
    } on DioException catch (e) {
      _error = e.response?.data?['error'] ?? 'Failed to accept booking';
      notifyListeners();
      return null;
    }
  }

  Future<void> declineRequest(String bookingId) async {
    try {
      await ApiClient.post('/api/bookings/$bookingId/decline', {});
      _pendingRequests.removeWhere((r) => r['id'] == bookingId);
      notifyListeners();
    } catch (_) {
      // Still remove locally to clean up UI
      _pendingRequests.removeWhere((r) => r['id'] == bookingId);
      notifyListeners();
    }
  }

  /// Current known status of a booking (active or completed), or null.
  String? statusForBooking(String bookingId) {
    for (final list in [_activePickups, _completedPickups]) {
      final match = list.firstWhere((p) => p['id'] == bookingId, orElse: () => const {});
      if (match.isNotEmpty) return match['status'] as String?;
    }
    return null;
  }

  /// Advances a job's status. Returns true on success. Clears any prior error
  /// first so a stale error can't block later calls (this caused a desync where
  /// the screen never advanced and re-sent 'collecting' → "collecting to
  /// collecting"). On a server state-conflict, syncs the local copy to the
  /// server's real status so the UI can recover.
  Future<bool> updateStatus(String bookingId, String action, {double? actualWeightKg, double? agreedAmount}) async {
    _error = null;
    try {
      final body = <String, dynamic>{};
      if (action == 'complete' && actualWeightKg != null) {
        body['actualWeightKg'] = actualWeightKg;
      }
      // Negotiated pricing: the price agreed with the household on-site.
      if (action == 'complete' && agreedAmount != null) {
        body['agreedAmount'] = agreedAmount;
      }
      await ApiClient.put('/api/bookings/$bookingId/$action', body.isEmpty ? null : body);
      const statusMap = {
        'on-the-way': 'ON_THE_WAY',
        'collecting': 'COLLECTING',
        'collected':  'COLLECTED',
        // Legacy aliases kept for backward compat
        'en-route':   'EN_ROUTE',
        'arrived':    'ARRIVED',
        'complete':   'COMPLETED',
      };
      final newStatus = statusMap[action];
      final idx = _activePickups.indexWhere((p) => p['id'] == bookingId);
      if (idx >= 0 && newStatus != null) {
        if (newStatus == 'COMPLETED') {
          final pickup = {..._activePickups[idx], 'status': newStatus, 'completedAt': DateTime.now().toIso8601String()};
          _activePickups.removeAt(idx);
          _completedPickups.insert(0, pickup);
        } else {
          _activePickups[idx] = {..._activePickups[idx], 'status': newStatus};
        }
      }
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _error = e.response?.data?['error'] ?? 'Failed to update job status';
      // If the server tells us the real current status, sync our copy so the
      // next action is derived from the correct state.
      final serverStatus = e.response?.data?['currentStatus'] as String?;
      if (serverStatus != null) {
        final idx = _activePickups.indexWhere((p) => p['id'] == bookingId);
        if (idx >= 0) _activePickups[idx] = {..._activePickups[idx], 'status': serverStatus};
      }
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Network error — status not saved';
      notifyListeners();
      return false;
    }
  }

  // ── Jobs for PickupsScreen ──────────────────────────────────────────────────
  List<Map<String, dynamic>> _allJobs  = [];
  bool _loadingJobs = false;

  List<Map<String, dynamic>> get assignedJobs =>
      _allJobs.where((b) => ['ASSIGNED', 'ACCEPTED', 'EN_ROUTE', 'ON_THE_WAY',
                              'ARRIVED', 'COLLECTING', 'COLLECTED'].contains(b['status'])).toList();
  List<Map<String, dynamic>> get pendingJobs =>
      _allJobs.where((b) => ['PENDING', 'SEARCHING', 'ASSIGNED']
          .contains(b['status'])).toList();
  List<Map<String, dynamic>> get completedJobs =>
      _allJobs.where((b) => b['status'] == 'COMPLETED').toList();
  bool get loadingJobs => _loadingJobs;

  Future<void> loadJobs() async {
    _loadingJobs = true;
    notifyListeners();
    try {
      // Assigned/completed bookings for this collector
      final res = await ApiClient.get('/api/bookings');
      final mine = List<Map<String, dynamic>>.from(res.data['data'] as List? ?? []);

      // Available PENDING bookings (unassigned, within 30 km)
      final avail = await ApiClient.get('/api/bookings/available');
      final available = List<Map<String, dynamic>>.from(avail.data['data'] as List? ?? []);

      // Merge: deduplicate by id
      final merged = <String, Map<String, dynamic>>{};
      for (final b in mine) {
        merged[b['id'] as String] = b;
      }
      for (final b in available) {
        merged.putIfAbsent(b['id'] as String, () => b);
      }
      _allJobs = merged.values.toList()
        ..sort((a, b) => (b['createdAt'] as String? ?? '').compareTo(a['createdAt'] as String? ?? ''));
    } catch (_) {
    } finally {
      _loadingJobs = false;
      notifyListeners();
    }
  }

  // ── Wallet / Payout ────────────────────────────────────────────────────────
  Map<String, dynamic>? _wallet;
  bool _loadingWallet = false;
  List<AppNotification> _notifications = [];
  int _unreadNotifications = 0;
  bool _loadingNotifications = false;
  String? _notificationError;

  double get walletAvailable  => Fmt.toDouble(_wallet?['available']);
  double get walletPending    => Fmt.toDouble(_wallet?['pending']);
  double get walletWithdrawn  => Fmt.toDouble(_wallet?['totalWithdrawn']);
  List<Map<String, dynamic>> get walletTransactions =>
      List<Map<String, dynamic>>.from(_wallet?['transactions'] as List? ?? []);
  bool get loadingWallet => _loadingWallet;
  List<AppNotification> get notifications => _notifications;
  int get unreadNotifications => _unreadNotifications;
  bool get loadingNotifications => _loadingNotifications;
  String? get notificationError => _notificationError;

  Future<void> loadWallet() async {
    _loadingWallet = true;
    notifyListeners();
    try {
      final res = await ApiClient.get('/api/collectors/wallet');
      _wallet = Map<String, dynamic>.from(res.data['data'] as Map);
    } catch (_) {}
    _loadingWallet = false;
    notifyListeners();
  }

  Future<void> loadNotifications({int page = 1}) async {
    _loadingNotifications = true;
    notifyListeners();
    try {
      final res = await ApiClient.get('/api/notifications', params: {'page': page, 'limit': 30});
      final data = Map<String, dynamic>.from(res.data['data'] as Map? ?? {});
      _notifications = List<Map<String, dynamic>>.from(data['notifications'] as List? ?? [])
          .map(AppNotification.fromJson)
          .toList();
      _unreadNotifications = (data['unreadCount'] as num?)?.toInt() ?? 0;
      _notificationError = null;
    } on DioException catch (e) {
      _notificationError = e.response?.data?['error'] ?? 'Could not load notifications';
    } finally {
      _loadingNotifications = false;
      notifyListeners();
    }
  }

  Future<bool> markNotificationRead(String id) async {
    try {
      final res = await ApiClient.patch('/api/notifications/$id/read', {});
      final unread = (res.data['data']?['unreadCount'] as num?)?.toInt();
      final idx = _notifications.indexWhere((n) => n.id == id);
      if (idx >= 0) {
        final item = _notifications[idx];
        _notifications[idx] = AppNotification(
          id: item.id,
          type: item.type,
          title: item.title,
          body: item.body,
          bookingId: item.bookingId,
          isRead: true,
          createdAt: item.createdAt,
        );
      }
      if (unread != null) _unreadNotifications = unread;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> markAllNotificationsRead() async {
    try {
      await ApiClient.patch('/api/notifications/read-all', {});
      _notifications = _notifications
          .map((item) => AppNotification(
                id: item.id,
                type: item.type,
                title: item.title,
                body: item.body,
                bookingId: item.bookingId,
                isRead: true,
                createdAt: item.createdAt,
              ))
          .toList();
      _unreadNotifications = 0;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestPayout(String momoNumber, double amount, String network) async {
    try {
      await ApiClient.post('/api/collectors/payout', {
        'momoNumber': momoNumber,
        'amount': amount,
        'network': network,
      });
      await loadWallet();
      return true;
    } on DioException catch (e) {
      _error = e.response?.data?['error'] ?? 'Payout request failed';
      notifyListeners();
      return false;
    }
  }

  // ── Exception / photo reporting ───────────────────────────────────────────
  Future<String?> uploadPhoto(String bookingId, String type, String filePath) async {
    try {
      final fileName = filePath.split('/').last;
      final formData = FormData.fromMap({
        'type': type,
        'photo': await MultipartFile.fromFile(filePath, filename: fileName),
      });

      final res = await ApiClient.upload('/api/bookings/$bookingId/photos', formData);
      return res.data['data']?['url'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ── No-show reporting ───────────────────────────────────────────────────────
  Future<bool> reportNoShow(String bookingId) async {
    try {
      await ApiClient.patch('/api/bookings/$bookingId/no-show', {});
      _activePickups.removeWhere((p) => p['id'] == bookingId);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── KYC / verification ──────────────────────────────────────────────────────
  Map<String, dynamic>? _kyc;
  String _accountStatus = 'PENDING';
  Map<String, dynamic>? get kyc => _kyc;
  String get accountStatus => _accountStatus;
  bool get isVerified => _accountStatus == 'ACTIVE';
  String get kycStatus => (_kyc?['status'] as String?) ?? 'NONE'; // NONE | PENDING | APPROVED | REJECTED
  String? get kycRejectionReason => _kyc?['rejectionReason'] as String?;

  Future<void> loadKyc() async {
    try {
      final res = await ApiClient.get('/api/collector/kyc');
      final data = res.data['data'] as Map<String, dynamic>?;
      _accountStatus = (data?['accountStatus'] as String?) ?? _accountStatus;
      _kyc = data?['kyc'] as Map<String, dynamic>?;
      notifyListeners();
    } catch (_) {}
  }

  /// Submits KYC documents. [files] maps field → local file path for any of
  /// 'ghanaCard', 'license', 'vehiclePhoto'. Returns null on success or an error.
  Future<String?> submitKyc({
    required Map<String, String> files,
    String? ghanaCardNumber,
    String? licenseNumber,
  }) async {
    try {
      final form = FormData();
      for (final entry in files.entries) {
        form.files.add(MapEntry(
          entry.key,
          await MultipartFile.fromFile(entry.value, filename: entry.value.split('/').last),
        ));
      }
      if (ghanaCardNumber != null && ghanaCardNumber.isNotEmpty) {
        form.fields.add(MapEntry('ghanaCardNumber', ghanaCardNumber));
      }
      if (licenseNumber != null && licenseNumber.isNotEmpty) {
        form.fields.add(MapEntry('licenseNumber', licenseNumber));
      }
      final res = await ApiClient.upload('/api/collector/kyc', form);
      _kyc = res.data['data'] as Map<String, dynamic>?;
      _accountStatus = 'PENDING';
      notifyListeners();
      return null;
    } on DioException catch (e) {
      return (e.response?.data is Map ? e.response?.data['error'] as String? : null) ?? 'Upload failed';
    } catch (_) {
      return 'Something went wrong. Please try again.';
    }
  }

  Future<bool> reportException(
      String bookingId, String reason, String? note, {String? photoUrl}) async {
    try {
      await ApiClient.patch('/api/bookings/$bookingId/exception', {
        'reason': reason,
        if (note != null && note.isNotEmpty) 'note': note,
        if (photoUrl != null && photoUrl.isNotEmpty) 'photoUrl': photoUrl,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    SocketService.off('booking:new');
    SocketService.off('booking:taken');
    SocketService.off('booking:completed');
    _listeningForBookings = false;
    super.dispose();
  }
}
