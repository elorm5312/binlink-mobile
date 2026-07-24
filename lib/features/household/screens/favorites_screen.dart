import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../core/design_system/household_design_system.dart';
import '../providers/household_provider.dart';
import 'book_screen.dart';

/// Favorite collectors — saved preferred collectors the household can re-request.
/// Tapping "Request pickup" opens the booking wizard with this collector set as
/// the preferred collector; dispatch offers them first when they're available.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await context.read<HouseholdProvider>().loadFavorites();
    if (mounted) setState(() => _loading = false);
  }

  void _request(Map<String, dynamic> collector) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BookScreen(
        mode: 'immediate',
        preferredCollectorId: collector['id'] as String?,
        preferredCollectorName: collector['fullName'] as String? ?? 'your collector',
      ),
    ));
  }

  Future<void> _remove(HouseholdProvider prov, Map<String, dynamic> collector) async {
    await prov.toggleFavorite(collector);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Removed from favorites')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<HouseholdProvider>();
    final favorites = prov.favorites;

    return Scaffold(
      backgroundColor: HouseholdColors.sand,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 18, 4),
            child: Row(children: [
              IconButton(
                onPressed: () => Navigator.maybePop(context),
                icon: Icon(PhosphorIcons.caretLeft(), color: HouseholdColors.forest, size: 22),
              ),
              Expanded(child: Text('Favorite collectors', style: HouseholdType.title)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text('Re-request a collector you trust. We offer them the job first when they\'re available.',
                style: HouseholdType.caption.copyWith(color: HouseholdColors.gray)),
          ),
          Expanded(child: _body(prov, favorites)),
        ]),
      ),
    );
  }

  Widget _body(HouseholdProvider prov, List<Map<String, dynamic>> favorites) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: HouseholdColors.primary));
    }
    if (favorites.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(PhosphorIcons.heart(), size: 52, color: HouseholdColors.gray),
            const SizedBox(height: 14),
            Text('No favorites yet', style: HouseholdType.section),
            const SizedBox(height: 6),
            Text('Tap the heart on a collector during a pickup to save them here.',
                textAlign: TextAlign.center,
                style: HouseholdType.caption.copyWith(color: HouseholdColors.gray)),
          ]),
        ),
      );
    }
    return RefreshIndicator(
      color: HouseholdColors.primary,
      onRefresh: prov.loadFavorites,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: favorites.length,
        itemBuilder: (_, i) => _FavoriteCard(
          collector: favorites[i],
          onRequest: () => _request(favorites[i]),
          onRemove: () => _remove(prov, favorites[i]),
        ),
      ),
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({required this.collector, required this.onRequest, required this.onRemove});
  final Map<String, dynamic> collector;
  final VoidCallback onRequest;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final name = collector['fullName'] as String? ?? 'Collector';
    final vehicle = collector['vehicleType'] as String?;
    final rating = (collector['rating'] as num?)?.toDouble();
    final online = collector['isOnline'] == true;
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: HCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: HouseholdColors.primary.withAlpha(28), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(initials, style: HouseholdType.section.copyWith(color: HouseholdColors.primary)),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: HouseholdType.section),
              const SizedBox(height: 2),
              Row(children: [
                if (rating != null) ...[
                  Icon(PhosphorIcons.star(PhosphorIconsStyle.fill), color: HouseholdColors.warning, size: 13),
                  const SizedBox(width: 4),
                  Text(rating.toStringAsFixed(1), style: HouseholdType.caption.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 10),
                ],
                if (vehicle != null) ...[
                  Text(vehicle, style: HouseholdType.caption.copyWith(color: HouseholdColors.gray)),
                  const SizedBox(width: 10),
                ],
                Container(width: 7, height: 7, decoration: BoxDecoration(
                    color: online ? HouseholdColors.ecoGreen : HouseholdColors.gray, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(online ? 'Online' : 'Offline', style: HouseholdType.caption.copyWith(
                    color: online ? HouseholdColors.ecoGreen : HouseholdColors.gray)),
              ]),
            ])),
            IconButton(
              onPressed: onRemove,
              icon: Icon(PhosphorIcons.heart(PhosphorIconsStyle.fill), color: HouseholdColors.danger, size: 22),
            ),
          ]),
          const SizedBox(height: 12),
          HButton(label: 'Request pickup', icon: 'pickup', onPressed: onRequest),
        ]),
      ),
    );
  }
}
