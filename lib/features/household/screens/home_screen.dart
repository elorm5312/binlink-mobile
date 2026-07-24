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
import 'wallet_screen.dart';

class HouseholdHomeScreen extends StatefulWidget {
  const HouseholdHomeScreen({super.key});

  @override
  State<HouseholdHomeScreen> createState() => _HouseholdHomeScreenState();
}

class _HouseholdHomeScreenState extends State<HouseholdHomeScreen> {
  int _index = 0;
  ll.LatLng? _myPos;
  ll.LatLng? _subscribedPos;
  StreamSubscription<Position>? _posSub;
  Timer? _collectorPollTimer;
  HouseholdProvider? _hp;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _collectorPollTimer?.cancel();
    _hp?.unsubscribeFromNearby();
    super.dispose();
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
    await Future.wait([
      _hp!.loadBookings(),
      _hp!.loadOnlineCollectors(lat: _myPos?.latitude, lng: _myPos?.longitude),
      _hp!.loadSubscriptions(),
      _hp!.loadSavedAddresses(),
    ]);
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
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.user?.isAdmin == true) {
      return const AdminDashboardScreen();
    }
    return Scaffold(
      backgroundColor: HouseholdColors.sand,
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: [
          HomeTab(myPos: _myPos, onTabSwitch: (i) => setState(() => _index = i)),
          const _PickupsTab(),
          const WalletScreen(),
          const HistoryTab(),
          const ProfileTab(),
        ],
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
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 116),
        children: [
          Text('Pickups', style: HouseholdType.hero),
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
