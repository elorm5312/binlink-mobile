import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../core/design_system/household_design_system.dart';
import '../../../shared/components/binlink_map.dart';
import '../../../shared/components/searching_radar_widget.dart';
import '../providers/household_provider.dart';
import '../screens/book_screen.dart';
import '../screens/tracking_screen.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key, required this.myPos, required this.onTabSwitch});
  final ll.LatLng? myPos;
  final ValueChanged<int> onTabSwitch;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  void _openBook({String mode = 'immediate'}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BookScreen(mode: mode, myPos: widget.myPos)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pos = widget.myPos;
    final provider = context.watch<HouseholdProvider>();
    if (pos == null) {
      return Center(child: SearchingRadarWidget(color: HouseholdColors.primary));
    }
    final active = provider.activeBooking;
    final pickupMarker = _pickupMarkerFor(active, pos);
    return Stack(
      children: [
        Positioned.fill(
          child: BinLinkMap(
            initialPosition: pos,
            collectors: provider.onlineCollectors,
            pickupPosition: pickupMarker,
          ),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 14,
          left: 18,
          right: 18,
          child: HCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            radius: 30,
            child: Row(children: [
              HIcon('location', color: HouseholdColors.primary),
              const SizedBox(width: 12),
              Expanded(child: Text('Where should we collect?', style: HouseholdType.section)),
              HIcon('search', color: HouseholdColors.charcoal),
            ]),
          ),
        ),
        if (provider.isSurging)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 80,
            left: 18,
            right: 18,
            child: _SurgeBanner(label: provider.surgeLabel, multiplier: provider.surgeMultiplier),
          ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 104,
          child: _BookingPanel(
            active: active,
            onBookNow: () => _openBook(mode: 'immediate'),
            onSchedule: () => _openBook(mode: 'scheduled'),
            onHistory: () => widget.onTabSwitch(3),
            onTrack: () {
              if (active != null) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => TrackingScreen(booking: active)));
              }
            },
          ),
        ),
      ],
    );
  }

  ll.LatLng? _pickupMarkerFor(Map<String, dynamic>? active, ll.LatLng userPos) {
    if (active == null) return null;
    final lat = (active['pickupLat'] as num?)?.toDouble();
    final lng = (active['pickupLng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    final distance = const ll.Distance().as(ll.LengthUnit.Meter, userPos, ll.LatLng(lat, lng));
    if (distance < 12) return null;
    return ll.LatLng(lat, lng);
  }
}

class _BookingPanel extends StatelessWidget {
  const _BookingPanel({
    required this.active,
    required this.onBookNow,
    required this.onSchedule,
    required this.onHistory,
    required this.onTrack,
  });
  final Map<String, dynamic>? active;
  final VoidCallback onBookNow;
  final VoidCallback onSchedule;
  final VoidCallback onHistory;
  final VoidCallback onTrack;

  @override
  Widget build(BuildContext context) {
    if (active != null) {
      final status = (active!['status'] as String? ?? 'SEARCHING').toUpperCase();
      if (status == 'PENDING' || status == 'SEARCHING') {
        return HCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              SizedBox(width: 92, height: 72, child: Center(child: SearchingRadarWidget(color: HouseholdColors.primary, size: 72))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Finding a collector...', style: HouseholdType.section),
                const SizedBox(height: 2),
                Text(active!['pickupAddress'] as String? ?? 'Matching the nearest collector now.', maxLines: 2, overflow: TextOverflow.ellipsis, style: HouseholdType.caption),
              ])),
            ]),
            const SizedBox(height: 14),
            HButton(label: 'Track pickup', icon: 'tracking', onPressed: onTrack),
          ]),
        );
      }

      final isArriving = ['ASSIGNED', 'ACCEPTED', 'EN_ROUTE', 'ON_THE_WAY', 'ARRIVED', 'COLLECTING'].contains(status);
      final isComplete = ['COMPLETED', 'COLLECTED'].contains(status);
      final asset = isComplete ? HouseholdAssets.complete : HouseholdAssets.arriving;
      final title = isComplete ? 'Pickup complete' : isArriving ? 'Collector arriving' : status.replaceAll('_', ' ');
      final copy = isComplete
          ? 'Collection done. Your receipt and impact record are ready.'
          : active!['pickupAddress'] as String? ?? 'Pickup in progress';
      return HCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            asset.endsWith('.svg')
                ? SvgPicture.asset(asset, height: 72, width: 88)
                : Image.asset(asset, height: 72, width: 88, fit: BoxFit.contain),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: HouseholdType.section),
              const SizedBox(height: 2),
              Text(copy, maxLines: 2, overflow: TextOverflow.ellipsis, style: HouseholdType.caption),
            ])),
          ]),
          const SizedBox(height: 14),
          if (!isComplete)
            HButton(label: 'Track pickup', icon: 'tracking', onPressed: onTrack)
          else
            HButton(label: 'View history', icon: 'history', secondary: true, onPressed: onHistory),
        ]),
      );
    }

    // No active booking — show two CTA cards
    return Column(mainAxisSize: MainAxisSize.min, children: [
      HCard(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('Ready to book?', style: HouseholdType.section),
          const SizedBox(height: 4),
          Text('Select waste type, bin size, address and pay — all in one flow.', style: HouseholdType.caption),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: _CtaCard(
                title: 'Request Now',
                sub: '~15 min arrival',
                icon: 'pickup',
                primary: true,
                onTap: onBookNow,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CtaCard(
                title: 'Schedule',
                sub: 'Pick date & time',
                icon: 'calendar',
                primary: false,
                onTap: onSchedule,
              ),
            ),
          ]),
        ]),
      ),
    ]);
  }
}

class _CtaCard extends StatelessWidget {
  const _CtaCard({required this.title, required this.sub, required this.icon, required this.primary, required this.onTap});
  final String title;
  final String sub;
  final String icon;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: primary ? HouseholdColors.primary : HouseholdColors.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: primary ? HouseholdColors.primary : HouseholdColors.border),
          boxShadow: primary
              ? [BoxShadow(color: HouseholdColors.primary.withAlpha(50), blurRadius: 16, offset: const Offset(0, 8))]
              : [BoxShadow(color: HouseholdColors.forest.withAlpha(12), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          HIcon(icon, size: 22, color: primary ? Colors.white : HouseholdColors.primary),
          const SizedBox(height: 10),
          Text(title, style: HouseholdType.section.copyWith(color: primary ? Colors.white : HouseholdColors.charcoal, fontSize: 15)),
          const SizedBox(height: 2),
          Text(sub, style: HouseholdType.caption.copyWith(color: primary ? Colors.white.withAlpha(180) : HouseholdColors.gray)),
        ]),
      ),
    );
  }
}

// _CategoryChip and _Selector removed — booking is now handled by BookScreen wizard

// ── Surge demand banner ───────────────────────────────────────────────────────
class _SurgeBanner extends StatelessWidget {
  const _SurgeBanner({required this.label, required this.multiplier});
  final String label;
  final double multiplier;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: HouseholdColors.warning.withAlpha(28),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: HouseholdColors.warning.withAlpha(110)),
      ),
      child: Row(children: [
        Icon(PhosphorIcons.lightning(PhosphorIconsStyle.fill), size: 18, color: HouseholdColors.warning),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: HouseholdType.caption.copyWith(
                color: HouseholdColors.charcoal, fontWeight: FontWeight.w700)),
            Text('Prices are higher right now', style: HouseholdType.caption.copyWith(
                color: HouseholdColors.gray, fontSize: 11)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: HouseholdColors.warning,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('${multiplier.toStringAsFixed(1)}×', style: HouseholdType.number.copyWith(
              color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
        ),
      ]),
    );
  }
}
