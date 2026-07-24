import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/design_system/collector_design_system.dart';
import '../../../core/routing/routing_service.dart';
import '../../../core/services/location_service.dart';
import '../../../shared/components/binlink_map.dart';

/// In-app turn-by-turn style navigation. Draws the live road route to a
/// destination on the map, follows the collector's GPS, and shows distance /
/// ETA â€” keeping the driver in-app instead of handing off to Google Maps.
class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key, required this.destination, required this.label});

  final ll.LatLng destination;
  final String label;

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  StreamSubscription<Position>? _sub;
  ll.LatLng? _myPos;
  double _heading = 0;
  RouteResult? _route;
  ll.LatLng? _lastRouteFrom;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final last = await LocationService.getLastKnownPosition();
    if (last != null && mounted) {
      setState(() => _myPos = ll.LatLng(last.latitude, last.longitude));
      _refreshRoute();
    }
    final cur = await LocationService.getCurrentPosition();
    if (cur != null && mounted) {
      setState(() => _myPos = ll.LatLng(cur.latitude, cur.longitude));
      _refreshRoute();
    }
    _sub = LocationService.getPositionStream().listen((p) {
      if (!mounted) return;
      setState(() {
        _myPos = ll.LatLng(p.latitude, p.longitude);
        if (p.heading >= 0) _heading = p.heading;
      });
      _refreshRoute();
    });
  }

  // Refetch the route only when we've moved >120m (keeps it cheap + smooth).
  Future<void> _refreshRoute() async {
    final from = _myPos;
    if (from == null) return;
    if (_lastRouteFrom != null &&
        const ll.Distance().as(ll.LengthUnit.Meter, _lastRouteFrom!, from) < 120) {
      return;
    }
    _lastRouteFrom = from;
    try {
      final route = await RoutingService.getRoute(from, widget.destination);
      if (mounted) setState(() => _route = route);
    } catch (_) {}
  }

  Future<void> _openExternal() async {
    final d = widget.destination;
    final uri = Uri.parse('google.navigation:q=${d.latitude},${d.longitude}&mode=d');
    final fallback = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${d.latitude},${d.longitude}&travelmode=driving');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    final arrived = _myPos != null &&
        const ll.Distance().as(ll.LengthUnit.Meter, _myPos!, widget.destination) < 40;

    return Scaffold(
      backgroundColor: CollectorColors.dark,
      body: Stack(children: [
        Positioned.fill(
          child: _myPos == null
              ? Center(child: CircularProgressIndicator(color: CollectorColors.green))
              : BinLinkMap(
                  initialPosition: _myPos!,
                  pickupPosition: widget.destination,
                  routePoints: route?.points ?? const [],
                  isNavigating: true,
                  myLocationEnabled: true,
                  myHeading: _heading,
                  initialZoom: 16,
                ),
        ),
        // Top instruction banner
        Positioned(
          top: MediaQuery.paddingOf(context).top + 12,
          left: 14,
          right: 14,
          child: CPanel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              IconButton(
                onPressed: () => Navigator.maybePop(context),
                icon: Icon(PhosphorIcons.caretLeft(), color: CollectorColors.white),
              ),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(arrived ? 'You have arrived' : 'Navigating to', style: CollectorType.caption),
                Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectorType.title),
              ])),
              if (route != null && !arrived)
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(route.etaLabel, style: CollectorType.title.copyWith(color: CollectorColors.green)),
                  Text('${route.distanceKm.toStringAsFixed(1)} km', style: CollectorType.caption),
                ]),
            ]),
          ),
        ),
        // Bottom controls
        Positioned(
          left: 16, right: 16, bottom: 24,
          child: Row(children: [
            Expanded(child: CButton(
              label: 'Open in Maps',
              icon: 'navigation',
              secondary: true,
              onPressed: _openExternal,
            )),
            const SizedBox(width: 10),
            Expanded(child: CButton(
              label: arrived ? 'Done' : 'Recenter',
              icon: arrived ? 'navigation' : 'location',
              onPressed: () {
                if (arrived) {
                  Navigator.maybePop(context);
                } else {
                  setState(() {}); // BinLinkMap recenters on rebuild with isNavigating
                }
              },
            )),
          ]),
        ),
      ]),
    );
  }
}
