import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../core/design_system/collector_design_system.dart';
import '../../../core/services/location_service.dart';
import '../components/collector_map_tab.dart';
import '../components/collector_profile_tab.dart';
import '../components/incoming_request_overlay.dart';
import '../providers/collector_provider.dart';
import 'collector_notifications_screen.dart';
import 'earnings_screen.dart';
import 'pickups_screen.dart';

class CollectorMapScreen extends StatefulWidget {
  const CollectorMapScreen({super.key});

  @override
  State<CollectorMapScreen> createState() => _CollectorMapScreenState();
}

class _CollectorMapScreenState extends State<CollectorMapScreen> {
  int _index = 0;
  LatLng? _pos;
  StreamSubscription<Position>? _sub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
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
          body: IndexedStack(
            index: _index,
            children: [
              CollectorMapTab(pos: _pos),
              const PickupsScreen(),
              const EarningsScreen(),
              const CollectorNotificationsScreen(),
              const CollectorProfileTab(),
            ],
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
