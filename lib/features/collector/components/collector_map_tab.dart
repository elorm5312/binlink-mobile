import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design_system/collector_design_system.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/components/binlink_map.dart';
import '../../../shared/screens/messages_screen.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/collector_provider.dart';
import '../screens/active_pickup_screen.dart';
import '../screens/navigation_screen.dart';
import '../screens/verification_screen.dart';

class CollectorMapTab extends StatelessWidget {
  const CollectorMapTab({super.key, required this.pos});
  final ll.LatLng? pos;

  // Fallback map centre (central Accra) so the UI — crucially the GO ONLINE
  // bar — still renders while GPS is resolving or if permission is denied.
  static const _fallbackCenter = ll.LatLng(5.6037, -0.1870);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CollectorProvider>();
    final user = context.watch<AuthProvider>().user;
    final p = pos ?? _fallbackCenter;
    final locating = pos == null;
    final capacity = ((user?.currentLoadKg ?? 0) / (user?.maxCapacityKg ?? 500) * 100).clamp(0, 100).round();
    final etaText = _etaText(provider.currentActivePickup);
    final verified = user?.status == 'ACTIVE';
    // The screen uses Scaffold(extendBody: true) with a floating 86px bottom
    // nav (CBottomNav: 72px bar + 14px margin). Bottom-anchored controls must
    // clear it, otherwise they render hidden behind the nav bar.
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    const navClearance = 86.0 + 12.0; // nav height + gap
    return Stack(
      children: [
        Positioned.fill(child: BinLinkMap(initialPosition: p, myLocationEnabled: provider.isOnline)),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 14,
          left: 16,
          right: 16,
          child: CPanel(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(children: [
              CIcon('map', color: CollectorColors.green),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(Fmt.currency(provider.todayEarnings), style: CollectorType.title),
                Text(provider.isOnline ? 'Online and receiving jobs' : 'Today\'s earnings', style: CollectorType.caption.copyWith(color: provider.isOnline ? CollectorColors.green : const Color(0xFFB6C0CC))),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: CollectorColors.dark, borderRadius: BorderRadius.circular(20)),
                child: Text('$capacity%', style: CollectorType.caption.copyWith(color: CollectorColors.green, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MessagesScreen())),
                child: Icon(PhosphorIcons.chatCircleDots(), color: CollectorColors.white),
              ),
            ]),
          ),
        ),
        // Truck-full dumpsite routing banner â€” above the GO button
        if (provider.isCapacityWarning)
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomInset + navClearance + 84,
            child: _DumpsiteBanner(
              loadPercent: provider.loadPercent,
              dumpsite: provider.nearestDumpsite,
              onNavigate: () {
                final d = provider.nearestDumpsite;
                final dlat = (d?['lat'] as num?)?.toDouble();
                final dlng = (d?['lng'] as num?)?.toDouble();
                if (dlat == null || dlng == null) return;
                Navigator.push(context, MaterialPageRoute(builder: (_) => NavigationScreen(
                  destination: ll.LatLng(dlat, dlng),
                  label: d?['name'] as String? ?? 'Nearest dumpsite',
                )));
              },
              onOffloaded: () => _confirmOffload(context, provider),
            ),
          ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 104,
          left: 22,
          child: _Metric(label: 'ETA', value: etaText),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 104,
          right: 22,
          child: _Metric(label: 'Speed', value: '${provider.currentSpeedKph.round()} km/h'),
        ),
        // Bottom bar: when there's an active pickup, show a persistent "resume
        // job" bar so the collector can always get back to the arrived/complete
        // controls (e.g. after Google Maps opened or they backgrounded the app).
        // Otherwise show the online/offline toggle.
        Positioned(
          left: 16, right: 16, bottom: bottomInset + navClearance,
          child: provider.currentActivePickup != null
              ? _ActiveJobBar(
                  booking: provider.currentActivePickup!,
                  onResume: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ActivePickupScreen(booking: provider.currentActivePickup!),
                    ),
                  ),
                )
              : _OnlineBar(
                  verified: verified,
                  isOnline: provider.isOnline,
                  locating: locating,
                  onTap: () async {
                    if (!verified) {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const VerificationScreen()));
                      return;
                    }
                    final messenger = ScaffoldMessenger.of(context);
                    final wasOnline = provider.isOnline;
                    final ok = await provider.toggleOnline();
                    if (!ok) {
                      messenger.showSnackBar(SnackBar(
                        backgroundColor: CollectorColors.red,
                        content: Text(provider.error ?? 'Could not go ${wasOnline ? 'offline' : 'online'}. Try again.'),
                      ));
                    }
                  },
                ),
        ),
        // The incoming-request takeover now lives at the shell level
        // (CollectorMapScreen) so it covers every tab + the nav bar.
      ],
    );
  }

  String _etaText(Map<String, dynamic>? booking) {
    final raw = booking?['etaMinutes'] ?? booking?['eta'] ?? booking?['estimatedMinutes'];
    final minutes = raw is num ? raw.round() : int.tryParse(raw?.toString() ?? '');
    if (minutes == null || minutes <= 0) return '--';
    return '$minutes min';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => CPanel(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: CollectorType.caption),
          Text(value, style: CollectorType.section),
        ]),
      );
}

Future<void> _confirmOffload(BuildContext context, CollectorProvider provider) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      backgroundColor: CollectorColors.charcoal,
      title: Text('Confirm offload', style: CollectorType.title),
      content: Text('Mark your truck as emptied at the dumpsite? This resets your load and resumes job matching.',
          style: CollectorType.caption),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: CollectorColors.green),
          onPressed: () => Navigator.pop(d, true),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  final dumpsite = provider.nearestDumpsite;
  final ok = await provider.dumpLoad(facilityId: dumpsite?['id'] as String?);
  messenger.showSnackBar(SnackBar(
    backgroundColor: ok ? CollectorColors.green : CollectorColors.red,
    content: Text(ok ? 'Load cleared â€” back to receiving jobs.' : 'Could not update. Try again.'),
  ));
}

class _DumpsiteBanner extends StatelessWidget {
  const _DumpsiteBanner({
    required this.loadPercent,
    required this.dumpsite,
    required this.onNavigate,
    required this.onOffloaded,
  });
  final int loadPercent;
  final Map<String, dynamic>? dumpsite;
  final VoidCallback onNavigate;
  final VoidCallback onOffloaded;

  @override
  Widget build(BuildContext context) {
    final name = dumpsite?['name'] as String? ?? 'Nearest dumpsite';
    final distance = (dumpsite?['distanceKm'] as num?)?.toDouble();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CollectorColors.charcoal,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CollectorColors.payout.withAlpha(160), width: 1.5),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 20, offset: Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: CollectorColors.payout.withAlpha(40), shape: BoxShape.circle),
            child: CIcon('truck', color: CollectorColors.payout),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Truck $loadPercent% full', style: CollectorType.title),
            Text(distance != null ? '$name Â· ${distance.toStringAsFixed(1)} km away' : name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectorType.caption),
          ])),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: dumpsite == null ? null : onNavigate,
            style: OutlinedButton.styleFrom(
              foregroundColor: CollectorColors.white,
              side: BorderSide(color: CollectorColors.line),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: CIcon('navigation', color: CollectorColors.white),
            label: Text('Navigate', style: CollectorType.caption.copyWith(color: CollectorColors.white)),
          )),
          const SizedBox(width: 10),
          Expanded(child: FilledButton(
            onPressed: onOffloaded,
            style: FilledButton.styleFrom(
              backgroundColor: CollectorColors.green,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text("I've offloaded", style: CollectorType.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
          )),
        ]),
      ]),
    );
  }
}

// ── Persistent active-job bar — always lets the collector resume the pickup ──
class _ActiveJobBar extends StatelessWidget {
  const _ActiveJobBar({required this.booking, required this.onResume});
  final Map<String, dynamic> booking;
  final VoidCallback onResume;

  String _label(String status) {
    switch (status) {
      case 'ACCEPTED':
      case 'ASSIGNED':
        return 'Head to pickup';
      case 'ON_THE_WAY':
      case 'EN_ROUTE':
        return 'On the way';
      case 'ARRIVED':
        return 'Arrived — start collecting';
      case 'COLLECTING':
        return 'Collecting — complete when done';
      case 'COLLECTED':
        return 'Finish the job';
      default:
        return 'Active pickup';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = booking['status'] as String? ?? 'ACCEPTED';
    final address = booking['pickupAddress'] as String? ?? 'Active pickup';
    return GestureDetector(
      onTap: onResume,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
          color: CollectorColors.charcoal,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: CollectorColors.green.withAlpha(160), width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 24, offset: Offset(0, 8))],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: CollectorColors.green.withAlpha(40), shape: BoxShape.circle),
            child: CIcon('jobs', color: CollectorColors.green),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_label(status), style: CollectorType.title),
            Text(address, maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectorType.caption),
          ])),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: CollectorColors.green,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text('RESUME', style: CollectorType.caption.copyWith(
              color: CollectorColors.dark, fontWeight: FontWeight.w900, letterSpacing: 0.5,
            )),
          ),
        ]),
      ),
    );
  }
}

// â”€â”€ Clean online/offline status bar (replaces the old floating GO circle) â”€â”€â”€â”€â”€
class _OnlineBar extends StatelessWidget {
  const _OnlineBar({required this.verified, required this.isOnline, required this.onTap, this.locating = false});
  final bool verified;
  final bool isOnline;
  final bool locating;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = !verified
        ? CollectorColors.warning
        : (isOnline ? CollectorColors.green : CollectorColors.green);
    final String title = !verified
        ? 'Get verified to start'
        : (isOnline ? "You're online" : "You're offline");
    final String sub = !verified
        ? 'Upload your documents for review'
        : (isOnline
            ? 'Receiving nearby pickups'
            : (locating ? 'Finding your location…' : 'Go online to start earning'));
    final String action = !verified ? 'VERIFY' : (isOnline ? 'GO OFFLINE' : 'GO ONLINE');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: CollectorColors.charcoal,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withAlpha(120), width: 1.5),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Row(children: [
        // Pulsing status dot
        Container(width: 12, height: 12, decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent,
          boxShadow: [BoxShadow(color: accent.withAlpha(140), blurRadius: 10, spreadRadius: 2)],
        )),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: CollectorType.title),
          Text(sub, style: CollectorType.caption),
        ])),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () { HapticFeedback.mediumImpact(); onTap(); },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: isOnline && verified ? Colors.transparent : accent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent, width: 1.5),
            ),
            child: Text(action, style: CollectorType.caption.copyWith(
              color: isOnline && verified ? accent : CollectorColors.dark,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            )),
          ),
        ),
      ]),
    );
  }
}
