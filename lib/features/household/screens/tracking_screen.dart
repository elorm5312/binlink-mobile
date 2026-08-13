import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/design_system/household_design_system.dart';
import '../../../core/services/phone_launcher.dart';
import '../../../core/routing/routing_service.dart';
import '../../../shared/components/binlink_map.dart';
import '../../../shared/screens/chat_screen.dart';
import '../providers/household_provider.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key, required this.booking});
  final Map<String, dynamic> booking;

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  late Map<String, dynamic> _booking;
  String _status = 'SEARCHING';
  RealtimeChannel? _supaChannel;
  bool _ratingShown = false;
  int? _roadEtaMin;
  ll.LatLng? _lastEtaFrom;
  List<ll.LatLng> _routePoints = const [];
  double _collectorBearing = 0.0;
  ll.LatLng? _prevCollectorPos;
  bool _arrivingBuzzed = false;

  @override
  void initState() {
    super.initState();
    _booking = Map<String, dynamic>.from(widget.booking);
    _status = (_booking['status'] as String? ?? 'SEARCHING').toUpperCase();
    final bookingId = _booking['id'] as String?;
    if (bookingId != null) {
      final prov = context.read<HouseholdProvider>();
      prov.listenToBooking(bookingId);
      prov.loadFavorites();
      _subscribeRealtime(bookingId);
    }
  }

  void _subscribeRealtime(String bookingId) {
    try {
      _supaChannel = Supabase.instance.client
          .channel('tracking_$bookingId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'booking_status_events',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'booking_id',
              value: bookingId,
            ),
            callback: (payload) {
              final s = payload.newRecord['status'] as String?;
              if (s != null && mounted) setState(() => _status = s.toUpperCase());
            },
          )
          .subscribe();
    } catch (_) {}
  }

  @override
  void dispose() {
    _supaChannel?.unsubscribe();
    context.read<HouseholdProvider>().stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<HouseholdProvider>();

    // Mirror status from provider (socket updates)
    final provStatus = (prov.activeBooking?['status'] as String?)?.toUpperCase();
    if (provStatus != null && provStatus != _status) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _status = provStatus);
      });
    }

    final pickupLat = (_booking['pickupLat'] as num?)?.toDouble();
    final pickupLng = (_booking['pickupLng'] as num?)?.toDouble();
    final pickupPos = pickupLat != null && pickupLng != null ? ll.LatLng(pickupLat, pickupLng) : null;

    final collectorLat = prov.collectorLat;
    final collectorLng = prov.collectorLng;

    final collector = (prov.activeBooking?['collector'] as Map<String, dynamic>?) ?? (_booking['collector'] as Map<String, dynamic>?);

    // Derive travel heading from consecutive positions so the truck points
    // the way it's driving (like Uber/Bolt).
    if (collectorLat != null && collectorLng != null) {
      final cur = ll.LatLng(collectorLat, collectorLng);
      final prev = _prevCollectorPos;
      if (prev != null && (prev.latitude != cur.latitude || prev.longitude != cur.longitude)) {
        _collectorBearing = const ll.Distance().bearing(prev, cur);
      }
      _prevCollectorPos = cur;
    }

    final collectorEntry = collectorLat != null && collectorLng != null
        ? <String, dynamic>{
            'id': collector?['id'] ?? 'live-collector',
            'lastLat': collectorLat,
            'lastLng': collectorLng,
            'bearing': _collectorBearing,
            'fullName': collector?['fullName'] ?? 'Collector',
          }
        : null;

    // Live ETA + distance — prefer real road-distance routing; fall back to
    // straight-line. Distance drives the "X km away" readout on the card.
    int? etaMinutes;
    double? distanceKm;
    final etaActive = const ['ASSIGNED', 'ACCEPTED', 'ON_THE_WAY', 'EN_ROUTE'].contains(_status);
    if (collectorLat != null && collectorLng != null && pickupPos != null && etaActive) {
      final from = ll.LatLng(collectorLat, collectorLng);
      _maybeRefreshRoadEta(from, pickupPos);
      final meters = const ll.Distance().as(ll.LengthUnit.Meter, from, pickupPos);
      distanceKm = meters / 1000;
      etaMinutes = _roadEtaMin ?? (meters / 1000 / 22 * 60).round().clamp(1, 120);
    } else {
      _roadEtaMin = null;
    }

    // Buzz once as the collector is about to arrive; re-arm if ETA grows again.
    if (etaActive && etaMinutes != null && etaMinutes <= 1 && !_arrivingBuzzed) {
      _arrivingBuzzed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => HapticFeedback.mediumImpact());
    } else if (etaMinutes != null && etaMinutes > 2) {
      _arrivingBuzzed = false;
    }

    // Auto-prompt a rating the moment the pickup completes.
    if (const ['COMPLETED', 'COLLECTED'].contains(_status) &&
        !_ratingShown && collector != null && _booking['review'] == null) {
      _ratingShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showRatingSheet(collector);
      });
    }

    final sosVisible = const ['ASSIGNED', 'ACCEPTED', 'ON_THE_WAY', 'EN_ROUTE', 'ARRIVED', 'COLLECTING']
        .contains(_status);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1821),
      body: Stack(
        children: [
          // ── Map ─────────────────────────────────────────────────────────────
          Positioned.fill(
            child: pickupPos != null
                ? BinLinkMap(
                    initialPosition: pickupPos,
                    pickupPosition: pickupPos,
                    collectors: collectorEntry != null ? [collectorEntry] : [],
                    routePoints: etaActive ? _routePoints : const [],
                    myLocationEnabled: false,
                  )
                : _DarkPlaceholder(status: _status),
          ),

          // ── Top bar ─────────────────────────────────────────────────────────
          Positioned(
            top: MediaQuery.paddingOf(context).top + 12,
            left: 14,
            right: 14,
            child: _TopBar(status: _status, onBack: () => Navigator.maybePop(context)),
          ),

          // ── SOS safety button ────────────────────────────────────────────────
          if (sosVisible)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 72,
              right: 14,
              child: _SosButton(onTap: () => _confirmSos(context, prov)),
            ),

          // ── Bottom card ──────────────────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomCard(
              booking: _booking,
              status: _status,
              collector: collector,
              etaMinutes: etaMinutes,
              distanceKm: distanceKm,
              onCall: () => _launchCall(collector?['phone'] as String?),
              onMessage: () => _openChat(collector),
              onFavorite: collector != null ? () => _toggleFavorite(prov, collector) : null,
              isFavorite: collector != null && prov.isFavorite(collector['id'] as String? ?? ''),
              onTip: () => _showTipSheet(context, prov),
              onCancel: () => _confirmCancel(context, prov),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchCall(String? phone) async {
    final ok = await PhoneLauncher.call(phone);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number available for your collector yet.')),
      );
    }
  }

  void _openChat(Map<String, dynamic>? collector) {
    final bookingId = _booking['id'] as String?;
    if (bookingId == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        bookingId: bookingId,
        peerName: collector?['fullName'] as String? ?? 'Your collector',
      ),
    ));
  }

  // Real road-distance ETA — refetched only when the collector moves >150m.
  Future<void> _maybeRefreshRoadEta(ll.LatLng from, ll.LatLng to) async {
    if (_lastEtaFrom != null &&
        const ll.Distance().as(ll.LengthUnit.Meter, _lastEtaFrom!, from) < 150) {
      return;
    }
    _lastEtaFrom = from;
    try {
      final route = await RoutingService.getRoute(from, to);
      if (mounted && route.travelTimeSec > 0) {
        setState(() {
          _roadEtaMin = route.travelTimeMin.clamp(1, 120);
          _routePoints = route.points; // drives the on-map route line
        });
      }
    } catch (_) {}
  }

  void _showRatingSheet(Map<String, dynamic> collector) {
    final bookingId = _booking['id'] as String?;
    if (bookingId == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: HouseholdColors.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _RatingSheet(
        bookingId: bookingId,
        collectorName: collector['fullName'] as String? ?? 'your collector',
        prov: context.read<HouseholdProvider>(),
      ),
    );
  }

  Future<void> _toggleFavorite(HouseholdProvider prov, Map<String, dynamic> collector) async {
    HapticFeedback.lightImpact();
    final added = !prov.isFavorite(collector['id'] as String? ?? '');
    final ok = await prov.toggleFavorite(collector);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(!ok
          ? 'Could not update favorites'
          : added
              ? 'Added to favorite collectors'
              : 'Removed from favorites'),
    ));
  }

  Future<void> _confirmSos(BuildContext ctx, HouseholdProvider prov) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (d) => AlertDialog(
        title: const Text('Send SOS alert?'),
        content: const Text(
            'This immediately alerts BinLink support with your live location and pickup details. Use only in an emergency.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HouseholdColors.danger),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Send SOS'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final collectorLat = prov.collectorLat;
    final collectorLng = prov.collectorLng;
    final lat = collectorLat ?? (_booking['pickupLat'] as num?)?.toDouble();
    final lng = collectorLng ?? (_booking['pickupLng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    final ok = await prov.raiseSos(lat: lat, lng: lng, bookingId: _booking['id'] as String?);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? HouseholdColors.ecoGreen : HouseholdColors.danger,
      content: Text(ok ? 'SOS sent — support has been alerted.' : 'Could not send SOS. Call support directly.'),
    ));
  }

  Future<void> _showTipSheet(BuildContext ctx, HouseholdProvider prov) async {
    final bookingId = _booking['id'] as String?;
    if (bookingId == null) return;
    await showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: HouseholdColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _TipSheet(bookingId: bookingId, prov: prov),
    );
  }

  void _confirmCancel(BuildContext ctx, HouseholdProvider prov) {
    // Mirror the backend policy so the user sees the fee before confirming.
    const committed = ['ACCEPTED', 'ON_THE_WAY', 'EN_ROUTE', 'ARRIVED', 'COLLECTING'];
    final created = DateTime.tryParse(_booking['createdAt'] as String? ?? '');
    final outsideGrace = created != null && DateTime.now().difference(created).inSeconds > 120;
    final feeApplies = committed.contains(_status) && outsideGrace;

    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: HouseholdColors.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.paddingOf(sheetCtx).bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: HouseholdColors.border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Text('Cancel this pickup?', style: HouseholdType.title),
          const SizedBox(height: 8),
          Text('You are limited to 3 cancellations per day.', style: HouseholdType.body.copyWith(color: HouseholdColors.gray)),
          if (feeApplies) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: HouseholdColors.warning.withAlpha(28),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: HouseholdColors.warning.withAlpha(110)),
              ),
              child: Row(children: [
                Icon(PhosphorIcons.warning(PhosphorIconsStyle.fill), color: HouseholdColors.warning, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  'A GHS 5 cancellation fee applies — your collector is already on the way. It will be charged from your wallet.',
                  style: HouseholdType.caption.copyWith(color: HouseholdColors.charcoal))),
              ]),
            ),
          ],
          const SizedBox(height: 24),
          HButton(
            label: 'Yes, cancel pickup',
            icon: 'security',
            onPressed: () async {
              Navigator.pop(sheetCtx);
              final id = _booking['id'] as String?;
              if (id == null) return;
              final nav = Navigator.of(ctx);
              await prov.cancelBooking(id, reason: 'Cancelled by household');
              if (mounted) nav.pushNamedAndRemoveUntil('/household', (_) => false);
            },
          ),
          const SizedBox(height: 10),
          HButton(label: 'Keep pickup', icon: 'pickup', secondary: true, onPressed: () => Navigator.pop(sheetCtx)),
        ]),
      ),
    );
  }
}

// ─── Top Bar ─────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.status, required this.onBack});
  final String status;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _PillBtn(icon: PhosphorIcons.caretLeft(), onTap: onBack),
      const SizedBox(width: 10),
      Expanded(
        child: HCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          radius: 30,
          child: Row(children: [
            _StatusDot(status: status),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _statusLabel(status),
                style: HouseholdType.section.copyWith(fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  static String _statusLabel(String s) {
    const m = {
      'SEARCHING': 'Searching for collector...',
      'ASSIGNED':  'Collector assigned',
      'ACCEPTED':  'Collector accepted',
      'EN_ROUTE':  'Collector on the way',
      'ON_THE_WAY': 'Collector on the way',
      'ARRIVED':   'Collector arrived',
      'COLLECTING': 'Collection in progress',
      'COLLECTED': 'Waste collected',
      'COMPLETED': 'Pickup complete',
      'CANCELLED': 'Pickup cancelled',
    };
    return m[s] ?? s.replaceAll('_', ' ');
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final String status;

  Color get _color {
    if (['COMPLETED', 'COLLECTED'].contains(status)) return const Color(0xFF22C55E);
    if (status == 'CANCELLED') return const Color(0xFFEF4444);
    if (['ARRIVED', 'COLLECTING'].contains(status)) return const Color(0xFF7C3AED);
    if (['EN_ROUTE', 'ON_THE_WAY', 'ACCEPTED', 'ASSIGNED'].contains(status)) return HouseholdColors.primary;
    return const Color(0xFFF59E0B);
  }

  @override
  Widget build(BuildContext context) {
    return Container(width: 9, height: 9, decoration: BoxDecoration(color: _color, shape: BoxShape.circle));
  }
}

// ─── Dark placeholder (while GPS resolves) ────────────────────────────────────

class _DarkPlaceholder extends StatelessWidget {
  const _DarkPlaceholder({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1821),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SvgPicture.asset(HouseholdAssets.searching, height: 120),
          const SizedBox(height: 16),
          Text('Acquiring location...', style: HouseholdType.section.copyWith(color: Colors.white)),
        ]),
      ),
    );
  }
}

// ─── Bottom Card ──────────────────────────────────────────────────────────────

class _BottomCard extends StatelessWidget {
  const _BottomCard({
    required this.booking,
    required this.status,
    required this.collector,
    required this.etaMinutes,
    required this.onCall,
    required this.onMessage,
    required this.onFavorite,
    required this.isFavorite,
    required this.onTip,
    required this.onCancel,
    this.distanceKm,
  });
  final Map<String, dynamic> booking;
  final String status;
  final Map<String, dynamic>? collector;
  final int? etaMinutes;
  final double? distanceKm;
  final VoidCallback onCall;
  final VoidCallback onMessage;
  final VoidCallback? onFavorite;
  final bool isFavorite;
  final VoidCallback onTip;
  final VoidCallback onCancel;

  bool get _canCancel => ['SEARCHING', 'ASSIGNED', 'ACCEPTED'].contains(status);
  bool get _isDone    => ['COMPLETED', 'COLLECTED', 'CANCELLED'].contains(status);
  bool get _canTip    => ['COMPLETED', 'COLLECTED'].contains(status) &&
      collector != null && booking['tipPaidAt'] == null;

  @override
  Widget build(BuildContext context) {
    final amount  = booking['totalAmount'];
    final address = booking['pickupAddress'] as String? ?? 'Pickup location';

    return Container(
      decoration: BoxDecoration(
        color: HouseholdColors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 28, offset: Offset(0, -8))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 10),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: HouseholdColors.border, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.paddingOf(context).bottom + 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Status label + live ETA
            Row(children: [
              Expanded(child: _StatusLabel(status: status)),
              if (etaMinutes != null) _EtaPill(minutes: etaMinutes!),
            ]),
            const SizedBox(height: 16),

            // Collector row
            if (collector != null) ...[
              _CollectorRow(
                collector: collector!,
                onCall: onCall,
                onMessage: onMessage,
                onFavorite: onFavorite,
                isFavorite: isFavorite,
                distanceKm: distanceKm,
              ),
              const SizedBox(height: 14),
              Divider(height: 1, color: HouseholdColors.border),
              const SizedBox(height: 14),
            ] else if (status == 'SEARCHING') ...[
              _SearchAnim(),
              const SizedBox(height: 14),
            ],

            // Address + amount
            Row(children: [
              Icon(PhosphorIcons.mapPin(), size: 15, color: HouseholdColors.gray),
              const SizedBox(width: 8),
              Expanded(
                child: Text(address, style: HouseholdType.caption.copyWith(color: HouseholdColors.charcoal), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ]),
            if (amount != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                Icon(PhosphorIcons.money(), size: 15, color: HouseholdColors.gray),
                const SizedBox(width: 8),
                // Negotiated bookings have no amount until the collector enters
                // the agreed price at completion.
                Text(
                  booking['pricingMode'] == 'NEGOTIATED' && ((num.tryParse('$amount') ?? 0) <= 0)
                      ? 'Price agreed with collector on arrival'
                      : 'GHS $amount',
                  style: HouseholdType.number.copyWith(color: HouseholdColors.primary, fontSize: 16),
                ),
              ]),
            ],
            const SizedBox(height: 16),

            // Tip CTA — after a completed pickup
            if (_canTip) ...[
              HButton(label: 'Tip your collector', icon: 'rewards', onPressed: onTip),
              const SizedBox(height: 10),
            ],

            // Actions
            if (_isDone)
              HButton(
                label: 'Back to home',
                icon: 'home',
                secondary: true,
                onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/household', (_) => false),
              )
            else if (_canCancel)
              HButton(label: 'Cancel pickup', icon: 'security', secondary: true, onPressed: onCancel),
          ]),
        ),
      ]),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.status});
  final String status;

  Color get _color {
    if (['COMPLETED', 'COLLECTED'].contains(status)) return HouseholdColors.ecoGreen;
    if (status == 'CANCELLED') return HouseholdColors.danger;
    if (['ARRIVED', 'COLLECTING'].contains(status)) return const Color(0xFF7C3AED);
    if (['EN_ROUTE', 'ON_THE_WAY', 'ACCEPTED', 'ASSIGNED'].contains(status)) return HouseholdColors.primary;
    return HouseholdColors.warning;
  }

  String get _label {
    const m = {
      'SEARCHING':  'Searching for a collector...',
      'ASSIGNED':   'Collector assigned',
      'ACCEPTED':   'Collector accepted your request',
      'EN_ROUTE':   'Collector is on the way',
      'ON_THE_WAY': 'Collector is on the way',
      'ARRIVED':    'Collector has arrived',
      'COLLECTING': 'Collection in progress',
      'COLLECTED':  'Waste has been collected',
      'COMPLETED':  'Pickup complete',
      'CANCELLED':  'Pickup cancelled',
    };
    return m[status] ?? status.replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: _color, shape: BoxShape.circle)),
      const SizedBox(width: 10),
      Expanded(child: Text(_label, style: HouseholdType.section.copyWith(color: _color))),
    ]);
  }
}

class _CollectorRow extends StatelessWidget {
  const _CollectorRow({
    required this.collector,
    required this.onCall,
    required this.onMessage,
    required this.onFavorite,
    required this.isFavorite,
    this.distanceKm,
  });
  final Map<String, dynamic> collector;
  final VoidCallback onCall;
  final VoidCallback onMessage;
  final VoidCallback? onFavorite;
  final bool isFavorite;
  final double? distanceKm;

  String? get _distanceLabel {
    final d = distanceKm;
    if (d == null) return null;
    if (d < 1) return '${(d * 1000).round()} m away';
    return '${d.toStringAsFixed(1)} km away';
  }

  @override
  Widget build(BuildContext context) {
    final name    = collector['fullName'] as String? ?? 'Your collector';
    final vehicle = collector['vehicleType'] as String?;
    final rating  = (collector['rating'] as num?)?.toDouble();
    final photo   = collector['profilePhoto'] as String?;
    final hasPhone = (collector['phone'] as String?)?.isNotEmpty == true;
    final away = _distanceLabel;

    return Row(children: [
      _Avatar(name: name, photoUrl: photo),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: HouseholdType.section),
          Row(children: [
            if (rating != null) ...[
              Icon(PhosphorIcons.star(PhosphorIconsStyle.fill), color: HouseholdColors.warning, size: 13),
              const SizedBox(width: 4),
              Text(rating.toStringAsFixed(1), style: HouseholdType.caption.copyWith(fontWeight: FontWeight.w700)),
            ],
            if (rating != null && vehicle != null) Text('  ·  ', style: HouseholdType.caption),
            if (vehicle != null) Flexible(child: Text(vehicle, style: HouseholdType.caption, overflow: TextOverflow.ellipsis)),
          ]),
          if (away != null)
            Text(away, style: HouseholdType.caption.copyWith(color: HouseholdColors.primary, fontWeight: FontWeight.w700)),
        ]),
      ),
      if (onFavorite != null) ...[
        _PillBtn(
          icon: isFavorite
              ? PhosphorIcons.heart(PhosphorIconsStyle.fill)
              : PhosphorIcons.heart(),
          onTap: onFavorite!,
          color: HouseholdColors.danger,
        ),
        const SizedBox(width: 8),
      ],
      _PillBtn(icon: PhosphorIcons.chatCircleDots(), onTap: onMessage, color: HouseholdColors.primary),
      if (hasPhone) const SizedBox(width: 8),
      if (hasPhone)
        _PillBtn(icon: PhosphorIcons.phone(), onTap: onCall, color: HouseholdColors.ecoGreen),
    ]);
  }
}

// ── Live ETA pill ────────────────────────────────────────────────────────────
class _EtaPill extends StatelessWidget {
  const _EtaPill({required this.minutes});
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final arriving = minutes <= 1;
    final color = arriving ? HouseholdColors.ecoGreen : HouseholdColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          arriving ? PhosphorIcons.mapPin(PhosphorIconsStyle.fill) : PhosphorIcons.timer(PhosphorIconsStyle.fill),
          size: 14, color: color),
        const SizedBox(width: 6),
        Text(arriving ? 'Arriving' : '~$minutes min', style: HouseholdType.caption.copyWith(
          color: color, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ── SOS safety button ────────────────────────────────────────────────────────
class _SosButton extends StatelessWidget {
  const _SosButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { HapticFeedback.heavyImpact(); onTap(); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: HouseholdColors.danger,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: HouseholdColors.danger.withAlpha(90), blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(PhosphorIcons.warning(PhosphorIconsStyle.fill), size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text('SOS', style: HouseholdType.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1)),
        ]),
      ),
    );
  }
}

// ── Tip sheet ────────────────────────────────────────────────────────────────
class _TipSheet extends StatefulWidget {
  const _TipSheet({required this.bookingId, required this.prov});
  final String bookingId;
  final HouseholdProvider prov;

  @override
  State<_TipSheet> createState() => _TipSheetState();
}

class _TipSheetState extends State<_TipSheet> {
  static const _presets = [5.0, 10.0, 20.0, 50.0];
  double? _selected = 10.0;
  bool _sending = false;
  bool _done = false;

  Future<void> _submit() async {
    final amount = _selected;
    if (amount == null || _sending) return;
    setState(() => _sending = true);
    final err = await widget.prov.tipCollector(widget.bookingId, amount);
    if (!mounted) return;
    if (err == null) {
      setState(() { _sending = false; _done = true; });
      return;
    }
    setState(() => _sending = false);
    final shortfall = widget.prov.tipShortfall;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(shortfall != null && shortfall > 0
          ? '$err — top up GHS ${shortfall.toStringAsFixed(2)} in your wallet.'
          : err),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: HouseholdColors.border, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 18),
        if (_done) ...[
          Center(child: Icon(PhosphorIcons.checkCircle(PhosphorIconsStyle.fill), size: 56, color: HouseholdColors.ecoGreen)),
          const SizedBox(height: 12),
          Center(child: Text('Tip sent — thank you!', style: HouseholdType.section)),
          const SizedBox(height: 4),
          Center(child: Text('Your collector receives 100% of the tip.', style: HouseholdType.caption.copyWith(color: HouseholdColors.gray))),
          const SizedBox(height: 20),
          HButton(label: 'Done', icon: 'home', onPressed: () => Navigator.pop(context)),
        ] else ...[
          Text('Tip your collector', style: HouseholdType.section),
          const SizedBox(height: 4),
          Text('Paid from your wallet. Collectors keep 100% of tips.', style: HouseholdType.caption.copyWith(color: HouseholdColors.gray)),
          const SizedBox(height: 18),
          Wrap(spacing: 10, runSpacing: 10, children: _presets.map((p) {
            final sel = _selected == p;
            return GestureDetector(
              onTap: () => setState(() => _selected = p),
              child: Container(
                width: 72,
                padding: const EdgeInsets.symmetric(vertical: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel ? HouseholdColors.primary.withAlpha(22) : HouseholdColors.sand,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: sel ? HouseholdColors.primary : Colors.transparent, width: 1.5),
                ),
                child: Text('GHS ${p.toStringAsFixed(0)}', style: HouseholdType.number.copyWith(
                  color: sel ? HouseholdColors.primary : HouseholdColors.charcoal, fontWeight: FontWeight.w700)),
              ),
            );
          }).toList()),
          const SizedBox(height: 22),
          HButton(
            label: _sending ? 'Sending…' : 'Send GHS ${_selected?.toStringAsFixed(0) ?? '0'} tip',
            icon: 'rewards',
            onPressed: _sending ? null : _submit,
          ),
        ],
      ]),
    );
  }
}

class _SearchAnim extends StatefulWidget {
  @override
  State<_SearchAnim> createState() => _SearchAnimState();
}

class _SearchAnimState extends State<_SearchAnim> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)),
      child: Row(children: [
        SvgPicture.asset(HouseholdAssets.searching, height: 44, width: 56),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Searching for a collector', style: HouseholdType.section),
            Text('Finding the nearest available driver.', style: HouseholdType.caption),
          ]),
        ),
      ]),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.photoUrl});
  final String name;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : name.isNotEmpty ? name[0].toUpperCase() : '?';
    final fallback = Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: HouseholdColors.primary.withAlpha(22),
        shape: BoxShape.circle,
        border: Border.all(color: HouseholdColors.primary.withAlpha(60)),
      ),
      child: Center(child: Text(initials, style: HouseholdType.section.copyWith(color: HouseholdColors.primary))),
    );
    if (photoUrl == null || photoUrl!.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(photoUrl!, width: 50, height: 50, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback),
    );
  }
}

// ── Auto rating sheet (shown when the pickup completes) ───────────────────────
class _RatingSheet extends StatefulWidget {
  const _RatingSheet({required this.bookingId, required this.collectorName, required this.prov});
  final String bookingId;
  final String collectorName;
  final HouseholdProvider prov;

  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  int _rating = 0;
  final _comment = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() { _comment.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_rating == 0 || _submitting) return;
    setState(() => _submitting = true);
    final ok = await widget.prov.submitReview(widget.bookingId, _rating, _comment.text.trim());
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Thanks for your feedback! 🙏' : 'Could not submit rating')));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: HouseholdColors.border, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 18),
        Text('Rate ${widget.collectorName}', style: HouseholdType.title),
        const SizedBox(height: 4),
        Text('How was your pickup?', style: HouseholdType.body.copyWith(color: HouseholdColors.gray)),
        const SizedBox(height: 18),
        Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (i) {
          final filled = i < _rating;
          return IconButton(
            onPressed: () { HapticFeedback.lightImpact(); setState(() => _rating = i + 1); },
            icon: Icon(PhosphorIcons.star(filled ? PhosphorIconsStyle.fill : PhosphorIconsStyle.regular),
                size: 38, color: filled ? HouseholdColors.warning : HouseholdColors.border),
          );
        }))),
        const SizedBox(height: 14),
        TextField(
          controller: _comment,
          maxLines: 2,
          style: HouseholdType.body,
          decoration: InputDecoration(
            hintText: 'Add a comment (optional)',
            filled: true,
            fillColor: HouseholdColors.sand,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 20),
        HButton(label: _submitting ? 'Submitting…' : 'Submit rating', icon: 'star',
            onPressed: _rating == 0 || _submitting ? null : _submit),
        const SizedBox(height: 8),
        Center(child: TextButton(onPressed: () => Navigator.pop(context),
            child: Text('Maybe later', style: HouseholdType.caption.copyWith(color: HouseholdColors.gray)))),
      ]),
    );
  }
}

class _PillBtn extends StatelessWidget {
  const _PillBtn({required this.icon, required this.onTap, this.color});
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? HouseholdColors.primary;
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.withAlpha(20), border: Border.all(color: c.withAlpha(80))),
        child: Center(child: Icon(icon, color: c, size: 20)),
      ),
    );
  }
}
