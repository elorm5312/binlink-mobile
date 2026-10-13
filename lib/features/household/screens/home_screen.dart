import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';

import '../../../core/design_system/household_design_system.dart';
import '../../../core/services/location_service.dart';
import '../../../shared/components/skeleton.dart';
import '../../admin/screens/admin_dashboard_screen.dart';
import '../../auth/providers/auth_provider.dart';
import '../components/history_tab.dart';
import '../components/home_tab.dart';
import '../components/profile_tab.dart';
import '../providers/household_provider.dart';
import 'tracking_screen.dart';
import 'wallet_screen.dart';
import 'package:binlink_mobile/shared/components/profile_completion_sheet.dart';
import 'package:binlink_mobile/core/network/socket_service.dart';
import 'package:binlink_mobile/shared/components/pending_payment_banner.dart';
import 'package:binlink_mobile/core/utils/json_num.dart';
import 'payment_screen.dart';

class HouseholdHomeScreen extends StatefulWidget {
  const HouseholdHomeScreen({super.key});

  @override
  State<HouseholdHomeScreen> createState() => _HouseholdHomeScreenState();
}

class _HouseholdHomeScreenState extends State<HouseholdHomeScreen> with WidgetsBindingObserver {
  int _index = 0;
  ll.LatLng? _myPos;
  ll.LatLng? _subscribedPos;
  StreamSubscription<Position>? _posSub;
  Timer? _collectorPollTimer;
  Timer? _acceptPollTimer;
  HouseholdProvider? _hp;
  StreamSubscription<Map<String, dynamic>>? _acceptSub;
  String? _listeningBookingId;
  String? _autoOpenedBookingId;
  bool _homeWasCovered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
    // A payment confirmed anywhere (this phone, webhook) refreshes bookings so
    // "Make payment" disappears and the booking shows as paid.
    SocketService.on('booking:paid', _onPaid);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ProfileCompletion.ensure(context);
    });
  }

  Widget? _paymentDueBanner(List<Map<String, dynamic>> unpaid) {
    if (unpaid.isEmpty) return null;
    final b = unpaid.first;
    final amount = jsonDouble(b['totalAmount']) ?? 0;
    return PendingPaymentBanner(
      title: 'Make payment now · GHS ${amount.toStringAsFixed(2)}',
      subtitle: unpaid.length == 1
          ? 'Your pickup is complete'
          : '${unpaid.length} completed pickups to pay for',
      actionLabel: 'PAY NOW',
      background: const Color(0xFFF59E0B),
      foreground: const Color(0xFF1A1205),
      accent: const Color(0xFF1A1205),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PaymentScreen(booking: Map<String, dynamic>.from(b)),
      )),
    );
  }

  void _onPaid(dynamic _) {
    if (mounted) context.read<HouseholdProvider>().loadBookings();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    // Back from background: reconnect the live feed and refresh bookings.
    SocketService.ensureConnected();
    final prov = context.read<HouseholdProvider>();
    prov.loadBookings();
    prov.loadOnlineCollectors();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SocketService.offHandler('booking:paid', _onPaid);
    _posSub?.cancel();
    _collectorPollTimer?.cancel();
    _acceptPollTimer?.cancel();
    _acceptSub?.cancel();
    _hp?.unsubscribeFromNearby();
    super.dispose();
  }

  static const _preAccept = ['PENDING', 'SEARCHING', 'ASSIGNED'];

  /// Keeps the socket booking-room + accept listener alive for the current
  /// active-but-not-yet-accepted booking, so the household is notified the
  /// instant a collector accepts — even while sitting on the home tab.
  void _ensureListeningToActive() {
    final active = _hp?.activeBooking;
    final id = active?['id'] as String?;
    final status = (active?['status'] as String?)?.toUpperCase();
    if (id != null && _preAccept.contains(status) && _listeningBookingId != id) {
      _hp!.listenToBooking(id);
      _listeningBookingId = id;
    }
  }

  /// Takes the household straight to the live tracking / collector-profile
  /// screen when their pickup is accepted (unless they're already on it).
  void _onBookingAccepted(Map<String, dynamic> booking) {
    if (!mounted) return;
    final id = booking['id'] as String?;
    if (id == null || id == _autoOpenedBookingId) return;
    // Don't push over a tracking screen the user already opened themselves.
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    _autoOpenedBookingId = id;
    Navigator.push(context, MaterialPageRoute(builder: (_) => TrackingScreen(booking: booking)));
  }

  Future<void> _init() async {
    final lastKnown = await LocationService.getLastKnownPosition();
    if (lastKnown != null && mounted) setState(() => _myPos = ll.LatLng(lastKnown.latitude, lastKnown.longitude));
    final pos = await LocationService.getCurrentPosition();
    if (pos != null && mounted) setState(() => _myPos = ll.LatLng(pos.latitude, pos.longitude));

    _posSub = LocationService.getPositionStream().listen((p) {
      if (!mounted) return;
      final newPos = ll.LatLng(p.latitude, p.longitude);
      setState(() => _myPos = newPos);
      if (_hp != null && _subscribedPos != null) {
        final dist = Geolocator.distanceBetween(_subscribedPos!.latitude, _subscribedPos!.longitude, newPos.latitude, newPos.longitude);
        if (dist > 800) {
          _hp!.unsubscribeFromNearby();
          _hp!.subscribeToNearby(newPos.latitude, newPos.longitude);
          _subscribedPos = newPos;
          _hp!.loadOnlineCollectors(lat: newPos.latitude, lng: newPos.longitude);
        }
      }
    });

    if (!mounted) return;
    _hp = context.read<HouseholdProvider>();
    _acceptSub = _hp!.onBookingAccepted.listen(_onBookingAccepted);
    await Future.wait([
      _hp!.loadBookings(),
      _hp!.loadOnlineCollectors(lat: _myPos?.latitude, lng: _myPos?.longitude),
      _hp!.loadSubscriptions(),
      _hp!.loadSavedAddresses(),
    ]);
    _ensureListeningToActive();
    if (_myPos != null && mounted) {
      _hp!.subscribeToNearby(_myPos!.latitude, _myPos!.longitude);
      _subscribedPos = _myPos;
      _hp!.loadSurge(_myPos!.latitude, _myPos!.longitude);
    }
    _collectorPollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final pos = _myPos;
      _hp?.loadOnlineCollectors(lat: pos?.latitude, lng: pos?.longitude);
      if (pos != null) _hp?.loadSurge(pos.latitude, pos.longitude);
    });
    // Fast fallback so "collector accepted / on the way" shows within seconds
    // even if the socket is slow. Self-guards: only hits the network while a
    // booking is still awaiting a collector.
    _acceptPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _hp?.pollActiveBookingStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.user?.isAdmin == true) {
      return const AdminDashboardScreen();
    }
    // When we return to the home route (e.g. after backing out of a tracking
    // screen, whose dispose tears down the socket handlers), re-arm the accept
    // listener so an incoming acceptance still routes the user to tracking.
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (isCurrent && _homeWasCovered) {
      _homeWasCovered = false;
      _listeningBookingId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureListeningToActive();
      });
    } else if (!isCurrent) {
      _homeWasCovered = true;
    }
    return Scaffold(
      backgroundColor: HouseholdColors.sand,
      extendBody: true,
      body: TopBannerScaffoldBody(
        banner: _paymentDueBanner(context.watch<HouseholdProvider>().unpaidPayments),
        child: IndexedStack(
          index: _index,
          children: [
            HomeTab(myPos: _myPos, onTabSwitch: (i) => setState(() => _index = i)),
            const _PickupsTab(),
            const WalletScreen(),
            const HistoryTab(),
            const ProfileTab(),
          ],
        ),
      ),
      bottomNavigationBar: HBottomNav(
        index: _index,
        onChanged: (i) => setState(() => _index = i),
        items: const [
          (label: 'Home', icon: 'home'),
          (label: 'Pickups', icon: 'pickups'),
          (label: 'Wallet', icon: 'wallet'),
          (label: 'History', icon: 'history'),
          (label: 'Profile', icon: 'profile'),
        ],
      ),
    );
  }
}

class _PickupsTab extends StatelessWidget {
  const _PickupsTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HouseholdProvider>();
    final bookings = provider.allBookings
        .where((b) => ['PENDING', 'SEARCHING', 'ASSIGNED', 'ACCEPTED', 'EN_ROUTE', 'ON_THE_WAY', 'ARRIVED', 'COLLECTING', 'COLLECTED'].contains(b['status']))
        .toList();
    return SafeArea(
      child: RefreshIndicator(
        color: HouseholdColors.primary,
        onRefresh: provider.loadBookings,
        child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 116),
        children: [
          Row(children: [
            Expanded(child: Text('Pickups', style: HouseholdType.hero)),
            IconButton(
              tooltip: 'Refresh',
              onPressed: provider.loading ? null : provider.loadBookings,
              icon: Icon(Icons.refresh_rounded, color: HouseholdColors.primary),
            ),
          ]),
          const SizedBox(height: 8),
          Text('Upcoming, searching, and active collection requests.', style: HouseholdType.body.copyWith(color: HouseholdColors.gray)),
          const SizedBox(height: 22),
          if (provider.loading)
            const SkeletonList(count: 4)
          else if (provider.error != null)
            const _HouseholdEmpty(asset: HouseholdAssets.networkError, title: 'Could not load pickups', copy: 'Unable to load pickups right now.')
          else if (bookings.isEmpty)
            const _HouseholdEmpty(asset: 'assets/household_assets/empty_states/no_history.svg', title: 'No pickups yet', copy: 'Book your first pickup from the map and track the collector live.')
          else
            ...bookings.map((b) => _PickupCard(booking: b)),
        ],
      ),
      ),
    );
  }
}

class _PickupCard extends StatelessWidget {
  const _PickupCard({required this.booking});
  final Map<String, dynamic> booking;

  @override
  Widget build(BuildContext context) {
    final status = booking['status'] as String? ?? 'PENDING';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: HCard(
        child: Row(
          children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: HouseholdColors.primary.withAlpha(24), borderRadius: BorderRadius.circular(18)), child: Center(child: HIcon('pickup', color: HouseholdColors.primary))),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(booking['pickupAddress'] as String? ?? 'Pickup address', maxLines: 1, overflow: TextOverflow.ellipsis, style: HouseholdType.section),
                const SizedBox(height: 4),
                Text(status.replaceAll('_', ' '), style: HouseholdType.caption.copyWith(color: HouseholdColors.primary, fontWeight: FontWeight.w700)),
              ]),
            ),
            HIcon('route', color: HouseholdColors.gray),
          ],
        ),
      ),
    );
  }
}

class _HouseholdEmpty extends StatelessWidget {
  const _HouseholdEmpty({required this.asset, required this.title, required this.copy});
  final String asset;
  final String title;
  final String copy;

  @override
  Widget build(BuildContext context) {
    return HCard(
      child: Column(children: [
        SizedBox(height: 190, child: SvgPicture.asset(asset)),
        Text(title, style: HouseholdType.title, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(copy, style: HouseholdType.body.copyWith(color: HouseholdColors.gray), textAlign: TextAlign.center),
      ]),
    );
  }
}
