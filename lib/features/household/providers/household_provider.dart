import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/socket_service.dart';
import '../../../core/gps/kalman_filter.dart';
import '../../../shared/models/app_notification.dart';
import '../../../shared/models/reward_models.dart';

// Zone event type constants
const _kZoneMove    = 'move';
const _kZoneOnline  = 'online';
const _kZoneOffline = 'offline';

class HouseholdProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _bookings = [];
  List<Map<String, dynamic>> _onlineCollectors = [];
  Map<String, dynamic>? _activeBooking;
  bool _loading = false;
  String? _error;

  // Live collector GPS during tracking (Kalman-smoothed)
  double? _collectorLat;
  double? _collectorLng;
  final _gpsSmoother = GpsSmoother();

  List<Map<String, dynamic>> get bookings => _bookings;
  List<Map<String, dynamic>> get onlineCollectors => _onlineCollectors;
  Map<String, dynamic>? get activeBooking => _activeBooking;
  bool get loading => _loading;
  String? get error => _error;
  double? get collectorLat => _collectorLat;
  double? get collectorLng => _collectorLng;

  // Fires when a collector accepts the active booking, carrying the up-to-date
  // booking (with collector profile). The home screen listens to this to take
  // the household straight to the live tracking / collector-profile screen.
  final _bookingAccepted = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onBookingAccepted => _bookingAccepted.stream;

  List<Map<String, dynamic>> get completedBookings =>
      _bookings.where((b) => b['status'] == 'COMPLETED').toList();

  // All bookings (for history + subscriptions display)
  List<Map<String, dynamic>> get allBookings => List.unmodifiable(_bookings);

  List<AppNotification> _notifications = [];
  int _unreadNotifications = 0;
  bool _loadingNotifications = false;
  String? _notificationError;

  List<AppNotification> get notifications => _notifications;
  int get unreadNotifications => _unreadNotifications;
  bool get loadingNotifications => _loadingNotifications;
  String? get notificationError => _notificationError;

  Map<String, dynamic>? _walletSummary;
  bool _loadingWallet = false;
  String? _walletError;

  bool get loadingWallet => _loadingWallet;
  String? get walletError => _walletError;
  double get walletBalance => ((_walletSummary?['balance'] as num?) ?? 0).toDouble();
  List<Map<String, dynamic>> get walletCredits => List<Map<String, dynamic>>.from(_walletSummary?['credits'] as List? ?? []);
  List<Map<String, dynamic>> get walletDebits => List<Map<String, dynamic>>.from(_walletSummary?['debits'] as List? ?? []);
  List<Map<String, dynamic>> get pendingTransactions => List<Map<String, dynamic>>.from(_walletSummary?['pendingTransactions'] as List? ?? []);
  List<Map<String, dynamic>> get refundTransactions => List<Map<String, dynamic>>.from(_walletSummary?['refunds'] as List? ?? []);
  List<Map<String, dynamic>> get walletTransactions => List<Map<String, dynamic>>.from(_walletSummary?['transactions'] as List? ?? []);
  int get ecoPoints => ((_walletSummary?['rewards']?['ecoPoints'] as num?) ?? 0).toInt();
  double get carbonSavedKg => ((_walletSummary?['rewards']?['carbonSavedKg'] as num?) ?? 0).toDouble();
  List<RewardLedger> get rewardLedger => (List<Map<String, dynamic>>.from(_walletSummary?['rewards']?['rewardLedger'] as List? ?? []))
      .map(RewardLedger.fromJson)
      .toList();
  List<RewardTransaction> get rewardTransactions => (List<Map<String, dynamic>>.from(_walletSummary?['rewards']?['rewardTransactions'] as List? ?? []))
      .map(RewardTransaction.fromJson)
      .toList();
  List<Coupon> get coupons => (List<Map<String, dynamic>>.from(_walletSummary?['rewards']?['coupons'] as List? ?? []))
      .map(Coupon.fromJson)
      .toList();
  List<Coupon> get availableRewards => (List<Map<String, dynamic>>.from(_walletSummary?['rewards']?['availableRewards'] as List? ?? []))
      .map(Coupon.fromJson)
      .toList();

  Future<void> loadBookings() async {
    _setLoading(true);
    try {
      final res = await ApiClient.get('/api/bookings');
      _bookings = List<Map<String, dynamic>>.from(res.data['data'] as List);
      _activeBooking = _bookings.firstWhere(
        (b) => ['PENDING', 'SEARCHING', 'ASSIGNED', 'ACCEPTED',
                 'EN_ROUTE', 'ON_THE_WAY', 'ARRIVED',
                 'COLLECTING', 'COLLECTED'].contains(b['status']),
        orElse: () => {},
      );
      if (_activeBooking?.isEmpty == true) _activeBooking = null;
      _error = null;
    } on DioException catch (e) {
      _error = e.response?.data?['error'] ?? 'Failed to load bookings';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadOnlineCollectors({double? lat, double? lng}) async {
    try {
      final params = <String, dynamic>{
        if (lat != null) 'lat': lat.toString(),
        if (lng != null) 'lng': lng.toString(),
        if (lat != null) 'radiusKm': '15',
      };
      final res = await ApiClient.get('/api/collectors/online', params: params.isNotEmpty ? params : null);
      _onlineCollectors = (res.data['data'] as List? ?? [])
          .whereType<Map>()
          .map((c) => _normalizeCollector(c.cast<String, dynamic>()))
          .where((c) => c != null)
          .cast<Map<String, dynamic>>()
          .toList();
      notifyListeners();
    } catch (_) {}
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

  Future<void> loadWalletSummary() async {
    _loadingWallet = true;
    notifyListeners();
    try {
      final res = await ApiClient.get('/api/profile/wallet');
      _walletSummary = Map<String, dynamic>.from(res.data['data'] as Map? ?? {});
      _walletError = null;
    } on DioException catch (e) {
      _walletError = e.response?.data?['error'] ?? 'Could not load wallet';
    } finally {
      _loadingWallet = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> initializeWalletTopUp(double amount) async {
    try {
      final res = await ApiClient.post('/api/payments/wallet/top-up/initialize', {'amount': amount});
      return Map<String, dynamic>.from(res.data['data'] as Map);
    } on DioException catch (e) {
      _walletError = e.response?.data?['error'] ?? 'Could not initialize wallet top-up';
      notifyListeners();
      return null;
    }
  }

  Future<bool> verifyWalletTopUp(String reference) async {
    try {
      await ApiClient.post('/api/payments/wallet/top-up/verify', {'reference': reference});
      await loadWalletSummary();
      await loadNotifications();
      return true;
    } on DioException catch (e) {
      _walletError = e.response?.data?['error'] ?? 'Could not verify wallet top-up';
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>?> createBooking({
    required String binSize,
    required int extraBags,
    required String pickupAddress,
    required double pickupLat,
    required double pickupLng,
    required String paymentMethod,
    String? wasteCategory,
    String? timePreference,
    double? estimatedWeightKg,
    String? addressNotes,
    DateTime? scheduledDate,
    String? frequency,
    String? preferredCollectorId,
    String? promoCode,
    String? pricingMode,
    List<String>? bulkyPhotos,
  }) async {
    _setLoading(true);
    conflictBookingId = null;
    try {
      final res = await ApiClient.post('/api/bookings', {
        'binSize': binSize,
        'extraBags': extraBags,
        'pickupAddress': pickupAddress,
        'pickupLat': pickupLat,
        'pickupLng': pickupLng,
        'paymentMethod': paymentMethod,
        if (wasteCategory != null) 'wasteCategory': wasteCategory,
        if (timePreference != null) 'timePreference': timePreference,
        if (estimatedWeightKg != null) 'estimatedWeightKg': estimatedWeightKg,
        if (addressNotes != null && addressNotes.isNotEmpty) 'addressNotes': addressNotes,
        if (scheduledDate != null) 'scheduledDate': scheduledDate.toIso8601String(),
        if (frequency != null) 'frequency': frequency,
        if (preferredCollectorId != null) 'preferredCollectorId': preferredCollectorId,
        if (promoCode != null && promoCode.isNotEmpty) 'promoCode': promoCode,
        if (pricingMode != null) 'pricingMode': pricingMode,
        if (bulkyPhotos != null && bulkyPhotos.isNotEmpty) 'bulkyPhotos': bulkyPhotos,
      });
      final booking = Map<String, dynamic>.from(res.data['data'] as Map);
      _bookings.insert(0, booking);
      _activeBooking = booking;
      _error = null;
      notifyListeners();
      return booking;
    } on DioException catch (e) {
      // 409 = an earlier pickup is still active — remember its id so the UI
      // can offer "view it" / "cancel it" instead of a dead-end error.
      if (e.response?.statusCode == 409) {
        conflictBookingId = e.response?.data?['bookingId'] as String?;
      }
      _error = e.response?.data?['error'] ?? 'Failed to create booking';
      notifyListeners();
      return null;
    } catch (e) {
      _error = 'Something went wrong. Please try again.';
      notifyListeners();
      return null;
    } finally {
      _setLoading(false);
    }
  }

  /// Set when createBooking fails with 409 (an active pickup already exists).
  String? conflictBookingId;

  /// Fetches a single booking by id, or null on failure.
  Future<Map<String, dynamic>?> fetchBooking(String id) async {
    try {
      final res = await ApiClient.get('/api/bookings/$id');
      return Map<String, dynamic>.from(res.data['data'] as Map);
    } catch (_) {
      return null;
    }
  }

  /// Uploads one bulky-item photo (before the booking exists) and returns its
  /// URL, or null on failure.
  Future<String?> uploadBulkyPhoto(String filePath) async {
    try {
      final fileName = filePath.split('/').last;
      final formData = FormData.fromMap({
        'photo': await MultipartFile.fromFile(filePath, filename: fileName),
      });
      final res = await ApiClient.upload('/api/bookings/bulky-photos', formData);
      return res.data['data']?['url'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ── Surge pricing ─────────────────────────────────────────────────────────
  Map<String, dynamic>? _surge;
  double get surgeMultiplier => ((_surge?['multiplier'] as num?) ?? 1.0).toDouble();
  String get surgeLevel => (_surge?['level'] as String?) ?? 'NORMAL';
  String get surgeLabel => (_surge?['label'] as String?) ?? 'Normal demand';
  bool get isSurging => surgeMultiplier > 1.0;

  Future<void> loadSurge(double lat, double lng) async {
    try {
      final res = await ApiClient.get('/api/bookings/surge', params: {'lat': lat, 'lng': lng});
      _surge = Map<String, dynamic>.from(res.data['data'] as Map);
      notifyListeners();
    } catch (_) {
      // Non-fatal — UI falls back to normal demand.
    }
  }

  // ── Tipping ───────────────────────────────────────────────────────────────
  /// Tips the collector for a completed booking. Returns null on success, or a
  /// user-facing error string. When the wallet is short, sets [tipShortfall].
  double? tipShortfall;
  Future<String?> tipCollector(String bookingId, double amount) async {
    tipShortfall = null;
    try {
      await ApiClient.post('/api/bookings/$bookingId/tip', {'amount': amount});
      await loadBookings();
      await loadWalletSummary();
      return null;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['requiresTopUp'] == true) {
        tipShortfall = ((data['shortfall'] as num?) ?? 0).toDouble();
      }
      return (data is Map ? data['error'] as String? : null) ?? 'Could not send tip';
    } catch (_) {
      return 'Something went wrong. Please try again.';
    }
  }

  // ── Favorite collectors ───────────────────────────────────────────────────
  List<Map<String, dynamic>> _favorites = [];
  List<Map<String, dynamic>> get favorites => List.unmodifiable(_favorites);
  bool isFavorite(String collectorId) =>
      _favorites.any((c) => c['id'] == collectorId);

  Future<void> loadFavorites() async {
    try {
      final res = await ApiClient.get('/api/profile/favorites');
      _favorites = List<Map<String, dynamic>>.from(res.data['data'] as List? ?? []);
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> toggleFavorite(Map<String, dynamic> collector) async {
    final id = collector['id'] as String?;
    if (id == null) return false;
    final wasFav = isFavorite(id);
    try {
      if (wasFav) {
        await ApiClient.delete('/api/profile/favorites/$id');
        _favorites.removeWhere((c) => c['id'] == id);
      } else {
        await ApiClient.post('/api/profile/favorites', {'collectorId': id});
        _favorites.insert(0, collector);
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Referral program ────────────────────────────────────────────────────────
  Map<String, dynamic>? _referral;
  Map<String, dynamic>? get referral => _referral;

  Future<void> loadReferral() async {
    try {
      final res = await ApiClient.get('/api/profile/referral');
      _referral = Map<String, dynamic>.from(res.data['data'] as Map);
      notifyListeners();
    } catch (_) {}
  }

  /// Applies a referral code. Returns null on success or an error message.
  Future<String?> applyReferralCode(String code) async {
    try {
      await ApiClient.post('/api/profile/referral/apply', {'code': code});
      await loadReferral();
      await loadWalletSummary();
      return null;
    } on DioException catch (e) {
      return (e.response?.data is Map ? e.response?.data['error'] as String? : null) ?? 'Could not apply code';
    } catch (_) {
      return 'Something went wrong. Please try again.';
    }
  }

  // ── Promo codes ─────────────────────────────────────────────────────────────
  /// Validates a promo code against an amount. Returns {discount, total} on
  /// success, or throws/returns null with an error string.
  Future<Map<String, dynamic>?> validatePromo(String code, double amount) async {
    try {
      final res = await ApiClient.post('/api/promos/validate', {'code': code, 'amount': amount});
      promoError = null;
      return Map<String, dynamic>.from(res.data['data'] as Map);
    } on DioException catch (e) {
      promoError = (e.response?.data is Map ? e.response?.data['error'] as String? : null) ?? 'Invalid code';
      return null;
    } catch (_) {
      promoError = 'Could not validate code';
      return null;
    }
  }
  String? promoError;

  // ── Ratings ─────────────────────────────────────────────────────────────────
  Future<bool> submitReview(String bookingId, int rating, String? comment) async {
    try {
      await ApiClient.post('/api/bookings/$bookingId/review', {
        'rating': rating,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      });
      await loadBookings();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── SOS safety alert ──────────────────────────────────────────────────────
  Future<bool> raiseSos({required double lat, required double lng, String? bookingId, String? note}) async {
    try {
      await ApiClient.post('/api/sos', {
        'lat': lat,
        'lng': lng,
        if (bookingId != null) 'bookingId': bookingId,
        if (note != null && note.isNotEmpty) 'note': note,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> cancelBooking(String bookingId, {String? reason}) async {
    try {
      await ApiClient.put('/api/bookings/$bookingId/cancel', {'reason': reason});
      await loadBookings();
      _error = null;
      return true;
    } on DioException catch (e) {
      _error = e.response?.data?['error'] ?? 'Failed to cancel booking';
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'An unexpected error occurred';
      notifyListeners();
      return false;
    }
  }

  void listenToBooking(String bookingId) {
    SocketService.joinBookingRoom(bookingId);

    SocketService.on('booking:accepted', (data) {
      try {
        _updateBookingStatus(bookingId, 'ACCEPTED');
        final d = data as Map<String, dynamic>;
        final collector = d['collector'];
        if (_activeBooking != null) {
          _activeBooking = {
            ..._activeBooking!,
            if (collector != null) 'collector': collector,
            'status': 'ACCEPTED',
          };
          notifyListeners();
          if (!_bookingAccepted.isClosed) {
            _bookingAccepted.add(Map<String, dynamic>.from(_activeBooking!));
          }
        }
      } catch (_) {}
    });

    SocketService.on('booking:status', (data) {
      try {
        final d = data as Map<String, dynamic>;
        final status = d['status'] as String?;
        if (d['bookingId'] != bookingId || status == null) return;
        _updateBookingStatus(bookingId, status);
        if (_activeBooking != null) {
          _activeBooking = {..._activeBooking!, 'status': status};
        }
        notifyListeners();
      } catch (_) {}
    });

    SocketService.on('collector:location', (data) {
      try {
        final d = data as Map<String, dynamic>;
        final rawLat = (d['lat'] as num?)?.toDouble();
        final rawLng = (d['lng'] as num?)?.toDouble();
        if (rawLat == null || rawLng == null) return;
        // Apply Kalman filter — rejects teleport glitches, smooths Ghana 3G noise
        final smooth = _gpsSmoother.process(rawLat, rawLng);
        if (smooth != null) {
          _collectorLat = smooth.lat;
          _collectorLng = smooth.lng;
          notifyListeners();
        }
      } catch (_) {}
    });
  }

  void stopListening() {
    SocketService.off('booking:accepted');
    SocketService.off('booking:status');
    SocketService.off('collector:location');
    _collectorLat = null;
    _collectorLng = null;
    _gpsSmoother.reset();
  }

  // ── Zone subscription — real-time nearby collector feed ────────────────────
  // Events: {event: 'move'|'online'|'offline', collectorId, lat?, lng?, bearing?}
  final _zoneEvents = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get zoneEventStream => _zoneEvents.stream;

  void subscribeToNearby(double lat, double lng) {
    unsubscribeFromNearby();
    SocketService.joinZone(lat, lng);
    SocketService.on('zone:collector', _onZoneCollector);
    SocketService.on('zone:online',    _onZoneOnline);
    SocketService.on('zone:offline',   _onZoneOffline);
  }

  void unsubscribeFromNearby() {
    SocketService.leaveZone();
    SocketService.off('zone:collector');
    SocketService.off('zone:online');
    SocketService.off('zone:offline');
  }

  void _onZoneCollector(dynamic data) {
    try {
      final d   = data as Map<String, dynamic>;
      final id  = d['collectorId'] as String;
      final lat = (d['lat'] as num?)?.toDouble();
      final lng = (d['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;

      final idx = _onlineCollectors.indexWhere((c) => c['id'] == id);
      if (idx >= 0) {
        // Update existing collector's position
        final updated = _normalizeCollector({
          ..._onlineCollectors[idx],
          'lastLat': lat,
          'lastLng': lng,
          if (d['bearing'] != null) 'bearing': (d['bearing'] as num).toDouble(),
        });
        if (updated == null) return;
        _onlineCollectors[idx] = updated;
      } else {
        // Collector appeared in zone without a zone:online event — add them
        final added = _normalizeCollector({
          'id':      id,
          'lastLat': lat,
          'lastLng': lng,
          'bearing': (d['bearing'] as num?)?.toDouble() ?? 0.0,
        });
        if (added == null) return;
        _onlineCollectors.add(added);
      }
      // Notify map to re-render collector layer
      notifyListeners();

      if (!_zoneEvents.isClosed) {
        _zoneEvents.add({...d, 'event': _kZoneMove});
      }
    } catch (_) {}
  }

  void _onZoneOnline(dynamic data) {
    try {
      final d   = data as Map<String, dynamic>;
      final id  = d['collectorId'] as String;
      final lat = (d['lat'] as num?)?.toDouble();
      final lng = (d['lng'] as num?)?.toDouble();
      // Without coordinates the marker would render at (0,0) in the ocean
      if (lat == null || lng == null) return;
      if (!_onlineCollectors.any((c) => c['id'] == id)) {
        final added = _normalizeCollector({
          'id':      id,
          'lastLat': lat,
          'lastLng': lng,
          'bearing': (d['bearing'] as num?)?.toDouble() ?? 0.0,
        });
        if (added == null) return;
        _onlineCollectors.add(added);
        notifyListeners();
      }
      if (!_zoneEvents.isClosed) _zoneEvents.add({...d, 'event': _kZoneOnline});
    } catch (_) {}
  }

  void _onZoneOffline(dynamic data) {
    try {
      final d    = data as Map<String, dynamic>;
      final id   = d['collectorId'] as String;
      final prev = _onlineCollectors.length;
      _onlineCollectors.removeWhere((c) => c['id'] == id);
      if (_onlineCollectors.length != prev) notifyListeners();
      if (!_zoneEvents.isClosed) _zoneEvents.add({...d, 'event': _kZoneOffline});
    } catch (_) {}
  }

  // ── Saved Addresses ────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _savedAddresses = [];

  List<Map<String, dynamic>> get savedAddresses => _savedAddresses;

  Future<void> loadSavedAddresses() async {
    try {
      final res = await ApiClient.get('/api/profile/addresses');
      _savedAddresses = List<Map<String, dynamic>>.from(
          res.data['data'] as List? ?? []);
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> addSavedAddress({
    required String label,
    required String address,
    double? lat,
    double? lng,
    String? gateNotes,
  }) async {
    try {
      final res = await ApiClient.post('/api/profile/addresses', {
        'label': label,
        'address': address,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (gateNotes != null && gateNotes.isNotEmpty) 'gateNotes': gateNotes,
      });
      final added = Map<String, dynamic>.from(res.data['data'] as Map);
      _savedAddresses.insert(0, added);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteSavedAddress(String id) async {
    _savedAddresses.removeWhere((a) => a['id'] == id);
    notifyListeners();
    try {
      await ApiClient.delete('/api/profile/addresses/$id');
    } catch (_) {
      await loadSavedAddresses();
    }
  }

  // ── Subscriptions ──────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _subscriptions = [];
  Map<String, dynamic>? _adminLiveOps;
  List<Map<String, dynamic>> _pricingRules = [];
  List<Map<String, dynamic>> _fleetVehicles = [];
  Map<String, dynamic>? _adminAnalytics;
  List<Map<String, dynamic>> _pendingCollectors = [];
  List<Map<String, dynamic>> _promos = [];
  bool _loadingAdmin = false;
  String? _adminError;

  List<Map<String, dynamic>> get subscriptions => _subscriptions;
  Map<String, dynamic>? get adminLiveOps => _adminLiveOps;
  List<Map<String, dynamic>> get pricingRules => _pricingRules;
  List<Map<String, dynamic>> get fleetVehicles => _fleetVehicles;
  Map<String, dynamic>? get adminAnalytics => _adminAnalytics;
  List<Map<String, dynamic>> get pendingCollectors => _pendingCollectors;
  List<Map<String, dynamic>> get promos => _promos;
  bool get loadingAdmin => _loadingAdmin;
  String? get adminError => _adminError;

  Future<void> loadSubscriptions() async {
    try {
      final res = await ApiClient.get('/api/subscriptions/mine');
      _subscriptions = List<Map<String, dynamic>>.from(
          res.data['data'] as List? ?? []);
      notifyListeners();
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> createSubscription({
    required String plan,
    required String binSize,
    required String pickupAddress,
    required double pickupLat,
    required double pickupLng,
    int? pickupDay,
    String? pickupTime,
    String? wasteType,
    String? addressNotes,
  }) async {
    try {
      final res = await ApiClient.post('/api/subscriptions', {
        'plan': plan,
        'binSize': binSize,
        'pickupAddress': pickupAddress,
        'pickupLat': pickupLat,
        'pickupLng': pickupLng,
        if (pickupDay != null) 'pickupDay': pickupDay,
        if (pickupTime != null) 'pickupTime': pickupTime,
        if (wasteType != null && wasteType.isNotEmpty) 'wasteType': wasteType,
        if (addressNotes != null && addressNotes.isNotEmpty)
          'addressNotes': addressNotes,
      });
      final sub = Map<String, dynamic>.from(res.data['data'] as Map);
      _subscriptions.insert(0, sub);
      notifyListeners();
      return sub;
    } on DioException catch (e) {
      _error = e.response?.data?['error'] ?? 'Failed to create subscription';
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateSubscription(String id, Map<String, dynamic> data) async {
    try {
      final res = await ApiClient.patch('/api/subscriptions/$id', data);
      final updated = Map<String, dynamic>.from(res.data['data'] as Map);
      final idx = _subscriptions.indexWhere((s) => s['id'] == id);
      if (idx >= 0) _subscriptions[idx] = updated;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> cancelSubscription(String id) async {
    try {
      await ApiClient.delete('/api/subscriptions/$id');
      final idx = _subscriptions.indexWhere((s) => s['id'] == id);
      if (idx >= 0) {
        _subscriptions[idx] = {..._subscriptions[idx], 'status': 'CANCELLED'};
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> pauseSubscription(String id) => updateSubscription(id, {'status': 'PAUSED'});

  Future<bool> resumeSubscription(String id) => updateSubscription(id, {'status': 'ACTIVE'});

  Future<bool> skipNextSubscriptionPickup(String id) async {
    try {
      final res = await ApiClient.patch('/api/subscriptions/$id/skip-next', {});
      final updated = Map<String, dynamic>.from(res.data['data'] as Map);
      final idx = _subscriptions.indexWhere((s) => s['id'] == id);
      if (idx >= 0) _subscriptions[idx] = updated;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> loadAdminDashboard({String range = 'daily'}) async {
    _loadingAdmin = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        ApiClient.get('/api/admin/live-operations'),
        ApiClient.get('/api/admin/pricing'),
        ApiClient.get('/api/admin/fleet/vehicles'),
        ApiClient.get('/api/admin/analytics/timeseries', params: {'range': range}),
        ApiClient.get('/api/admin/collectors/pending'),
        ApiClient.get('/api/admin/promos'),
      ]);
      _adminLiveOps = Map<String, dynamic>.from(results[0].data['data'] as Map? ?? {});
      _pricingRules = List<Map<String, dynamic>>.from(results[1].data['data'] as List? ?? []);
      _fleetVehicles = List<Map<String, dynamic>>.from(results[2].data['data'] as List? ?? []);
      _adminAnalytics = Map<String, dynamic>.from(results[3].data['data'] as Map? ?? {});
      _pendingCollectors = List<Map<String, dynamic>>.from(results[4].data['data'] as List? ?? []);
      _promos = List<Map<String, dynamic>>.from(results[5].data['data'] as List? ?? []);
      _adminError = null;
    } on DioException catch (e) {
      _adminError = e.response?.data?['error'] ?? 'Could not load admin dashboard';
    } finally {
      _loadingAdmin = false;
      notifyListeners();
    }
  }

  /// Admin approves or rejects a pending collector's verification.
  Future<bool> reviewCollector(String collectorId, String action, {String? reason}) async {
    try {
      await ApiClient.patch('/api/admin/collectors/$collectorId/verify', {
        'action': action,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      });
      _pendingCollectors.removeWhere((c) => c['id'] == collectorId);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Admin creates a promo code.
  Future<bool> createPromoCode(Map<String, dynamic> payload) async {
    try {
      final res = await ApiClient.post('/api/admin/promos', payload);
      _promos.insert(0, Map<String, dynamic>.from(res.data['data'] as Map));
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> savePricingRule(Map<String, dynamic> payload, {String? id}) async {
    try {
      final res = id == null
          ? await ApiClient.post('/api/admin/pricing', payload)
          : await ApiClient.patch('/api/admin/pricing/$id', payload);
      final rule = Map<String, dynamic>.from(res.data['data'] as Map);
      final idx = _pricingRules.indexWhere((item) => item['id'] == rule['id']);
      if (idx >= 0) {
        _pricingRules[idx] = rule;
      } else {
        _pricingRules.insert(0, rule);
      }
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _adminError = e.response?.data?['error'] ?? 'Could not save pricing rule';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deletePricingRule(String id) async {
    try {
      await ApiClient.delete('/api/admin/pricing/$id');
      _pricingRules.removeWhere((item) => item['id'] == id);
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _adminError = e.response?.data?['error'] ?? 'Could not delete pricing rule';
      notifyListeners();
      return false;
    }
  }

  Future<bool> saveVehicle(Map<String, dynamic> payload, {String? id}) async {
    try {
      final res = id == null
          ? await ApiClient.post('/api/admin/fleet/vehicles', payload)
          : await ApiClient.patch('/api/admin/fleet/vehicles/$id', payload);
      final vehicle = Map<String, dynamic>.from(res.data['data'] as Map);
      final idx = _fleetVehicles.indexWhere((item) => item['id'] == vehicle['id']);
      if (idx >= 0) {
        _fleetVehicles[idx] = {
          ..._fleetVehicles[idx],
          ...vehicle,
        };
      } else {
        _fleetVehicles.insert(0, vehicle);
      }
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _adminError = e.response?.data?['error'] ?? 'Could not save vehicle';
      notifyListeners();
      return false;
    }
  }

  Future<bool> addVehicleMaintenance(String vehicleId, Map<String, dynamic> payload) async {
    try {
      final res = await ApiClient.post('/api/admin/fleet/vehicles/$vehicleId/maintenance', payload);
      final log = Map<String, dynamic>.from(res.data['data'] as Map);
      final idx = _fleetVehicles.indexWhere((item) => item['id'] == vehicleId);
      if (idx >= 0) {
        final current = List<Map<String, dynamic>>.from(_fleetVehicles[idx]['maintenanceLogs'] as List? ?? []);
        current.insert(0, log);
        _fleetVehicles[idx] = {
          ..._fleetVehicles[idx],
          'maintenanceLogs': current,
        };
      }
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _adminError = e.response?.data?['error'] ?? 'Could not add maintenance log';
      notifyListeners();
      return false;
    }
  }

  void _updateBookingStatus(String bookingId, String status) {
    final idx = _bookings.indexWhere((b) => b['id'] == bookingId);
    if (idx >= 0) {
      _bookings[idx] = {..._bookings[idx], 'status': status};
    }
  }

  Map<String, dynamic>? _normalizeCollector(Map<String, dynamic> raw) {
    final id = raw['id'] ?? raw['collectorId'];
    final lat = (raw['lastLat'] ?? raw['lat']) as num?;
    final lng = (raw['lastLng'] ?? raw['lng']) as num?;
    final lastLat = lat?.toDouble();
    final lastLng = lng?.toDouble();
    if (id == null || lastLat == null || lastLng == null) return null;
    if (lastLat < -90 || lastLat > 90 || lastLng < -180 || lastLng > 180) {
      return null;
    }
    return {
      ...raw,
      'id': id.toString(),
      'lastLat': lastLat,
      'lastLng': lastLng,
      'bearing': (raw['bearing'] as num?)?.toDouble() ?? 0.0,
    };
  }

  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }

  @override
  void dispose() {
    stopListening();
    unsubscribeFromNearby();
    _zoneEvents.close();
    _bookingAccepted.close();
    super.dispose();
  }

  // ── Test-only setters ───────────────────────────────────────────────────────
  @visibleForTesting
  set bookingsForTest(List<Map<String, dynamic>> bookings) {
    _bookings = bookings;
    _activeBooking = _bookings.where((b) => [
      'PENDING', 'SEARCHING', 'ASSIGNED', 'ACCEPTED',
      'EN_ROUTE', 'ON_THE_WAY', 'ARRIVED', 'COLLECTING', 'COLLECTED',
    ].contains(b['status'])).firstOrNull;
  }

  @visibleForTesting
  set subscriptionsForTest(List<Map<String, dynamic>> subs) {
    _subscriptions = subs;
  }
}
