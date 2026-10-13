import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../core/design_system/collector_design_system.dart';
import '../../../core/network/socket_service.dart';
import '../../../core/services/location_service.dart';
import '../components/collector_map_tab.dart';
import '../components/collector_profile_tab.dart';
import '../components/incoming_request_overlay.dart';
import '../providers/collector_provider.dart';
import 'collector_notifications_screen.dart';
import 'earnings_screen.dart';
import 'pickups_screen.dart';
import 'package:binlink_mobile/shared/components/profile_completion_sheet.dart';
import 'package:binlink_mobile/shared/components/pending_payment_banner.dart';
import 'package:binlink_mobile/core/utils/json_num.dart';
import 'awaiting_payment_screen.dart';

class CollectorMapScreen extends StatefulWidget {
  const CollectorMapScreen({super.key});

  @override
  State<CollectorMapScreen> createState() => _CollectorMapScreenState();
}

class _CollectorMapScreenState extends State<CollectorMapScreen> with WidgetsBindingObserver {
  int _index = 0;
  LatLng? _pos;
  StreamSubscription<Position>? _sub;

  Timer? _jobPoll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
    // Payment confirmed → refresh so the pending-payment banner disappears.
    SocketService.on('booking:paid', _onPaid);
    // Socket backup: while online, re-check open jobs every 15 s.
    _jobPoll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      final prov = context.read<CollectorProvider>();
      if (prov.isOnline) prov.refreshAvailableJobs();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ProfileCompletion.ensure(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SocketService.offHandler('booking:paid', _onPaid);
    _jobPoll?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  /// Completed jobs the household hasn't paid for yet.
  Widget? _pendingPaymentBanner(CollectorProvider prov) {
    final unpaid = unpaidCompleted(prov.completedPickups);
    if (unpaid.isEmpty) return null;
    final b = unpaid.first;
    final amount = jsonDouble(b['totalAmount']) ?? 0;
    final who = (b['household'] as Map?)?['fullName'] as String?;
    return PendingPaymentBanner(
      title: unpaid.length == 1
          ? 'Pending payment · GHS ${amount.toStringAsFixed(2)}'
          : '${unpaid.length} pending payments',
      subtitle: who != null ? "$who hasn't paid yet" : "The customer hasn't paid yet",
      actionLabel: 'VIEW',
      background: CollectorColors.warning,
      foreground: const Color(0xFF1A1205),
      accent: const Color(0xFF1A1205),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AwaitingPaymentScreen(bookingId: b['id'] as String, amount: amount),
      )),
    );
  }

  void _onPaid(dynamic _) {
    if (mounted) context.read<CollectorProvider>().loadDashboard();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    // Back from background: reconnect the live feed and catch up on jobs.
    SocketService.ensureConnected();
    final prov = context.read<CollectorProvider>();
    prov.syncOnlineFromServer();
    prov.refreshAvailableJobs();
    prov.loadDashboard();
  }

  Future<void> _init() async {
    final last = await LocationService.getLastKnownPosition();
    if (last != null && mounted) setState(() => _pos = LatLng(last.latitude, last.longitude));
    final pos = await LocationService.getCurrentPosition();
    if (pos != null && mounted) setState(() => _pos = LatLng(pos.latitude, pos.longitude));
    if (mounted) {
      final prov = context.read<CollectorProvider>();
      await prov.loadDashboard();
      // Restore online status if the collector never went offline.
      await prov.syncOnlineFromServer();
    }
    _sub = LocationService.getPositionStream().listen((p) {
      if (mounted) setState(() => _pos = LatLng(p.latitude, p.longitude));
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<CollectorProvider>();
    // Take over the WHOLE screen (all tabs + nav bar) when a job comes in while
    // online — the overlay sits above the Scaffold in a root Stack.
    final showRequest = prov.isOnline && prov.pendingRequests.isNotEmpty;
    return Stack(
      children: [
        Scaffold(
          backgroundColor: CollectorColors.dark,
          extendBody: true,
          body: TopBannerScaffoldBody(
            banner: _pendingPaymentBanner(prov),
            child: IndexedStack(
              index: _index,
              children: [
                CollectorMapTab(pos: _pos),
                const PickupsScreen(),
                const EarningsScreen(),
                const CollectorNotificationsScreen(),
                const CollectorProfileTab(),
              ],
            ),
          ),
          bottomNavigationBar: CBottomNav(
            index: _index,
            onChanged: (i) => setState(() => _index = i),
            items: const [
              (label: 'Map', icon: 'map'),
              (label: 'Jobs', icon: 'jobs'),
              (label: 'Wallet', icon: 'wallet'),
              (label: 'Alerts', icon: 'notifications'),
              (label: 'Profile', icon: 'profile'),
            ],
          ),
        ),
        if (showRequest)
          Positioned.fill(child: IncomingRequestOverlay(request: prov.pendingRequests.first)),
      ],
    );
  }
}
