import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../../core/design_system/household_design_system.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/receipt_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/components/skeleton.dart';
import '../providers/household_provider.dart';

class HistoryTab extends StatelessWidget {
  const HistoryTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HouseholdProvider>();
    final bookings = provider.completedBookings;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 116),
        children: [
          Text('History', style: HouseholdType.hero),
          const SizedBox(height: 8),
          Text('Receipts, carbon savings, past pickups, and service records.', style: HouseholdType.body.copyWith(color: HouseholdColors.gray)),
          const SizedBox(height: 22),
          if (provider.loading)
            const SkeletonList(count: 4)
          else if (provider.error != null)
            HCard(child: Column(children: [
              SvgPicture.asset(HouseholdAssets.networkError, height: 210),
              Text('History unavailable', style: HouseholdType.title),
              const SizedBox(height: 8),
              Text(provider.error!, textAlign: TextAlign.center, style: HouseholdType.body.copyWith(color: HouseholdColors.gray)),
            ]))
          else if (bookings.isEmpty)
            HCard(child: Column(children: [
              SvgPicture.asset(HouseholdAssets.noHistory, height: 210),
              Text('No history yet', style: HouseholdType.title),
              const SizedBox(height: 8),
              Text('Completed pickups and receipts will appear here.', textAlign: TextAlign.center, style: HouseholdType.body.copyWith(color: HouseholdColors.gray)),
            ]))
          else ...[
            _ImpactCard(count: bookings.length),
            const SizedBox(height: 16),
            ...bookings.map((b) => _HistoryTile(booking: b)),
          ],
        ],
      ),
    );
  }
}

class _ImpactCard extends StatelessWidget {
  const _ImpactCard({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return HCard(
      color: HouseholdColors.forest,
      child: Row(children: [
        SvgPicture.asset('assets/household_assets/history/carbon_saved.svg', height: 90),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$count pickups tracked', style: HouseholdType.title.copyWith(color: Colors.white)),
          const SizedBox(height: 5),
          Text('Your household impact record is building with every collection.', style: HouseholdType.caption.copyWith(color: Colors.white70)),
        ])),
      ]),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.booking});
  final Map<String, dynamic> booking;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _showBookingSheet(context, booking),
        child: HCard(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            HIcon('payment', color: HouseholdColors.primary),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(booking['pickupAddress'] as String? ?? 'Pickup receipt', maxLines: 1, overflow: TextOverflow.ellipsis, style: HouseholdType.section),
              Text((booking['status'] as String? ?? 'PENDING').replaceAll('_', ' '), style: HouseholdType.caption),
            ])),
            Text('GHS ${booking['totalAmount'] ?? '--'}', style: HouseholdType.caption.copyWith(fontWeight: FontWeight.w800, color: HouseholdColors.forest)),
          ]),
        ),
      ),
    );
  }

  Future<void> _showBookingSheet(BuildContext context, Map<String, dynamic> booking) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _HistorySheet(booking: booking),
    );
  }
}

class _HistorySheet extends StatefulWidget {
  const _HistorySheet({required this.booking});
  final Map<String, dynamic> booking;

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  bool _submitting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final review = widget.booking['review'] as Map<String, dynamic>?;
    return Container(
      decoration: BoxDecoration(
        color: HouseholdColors.sand,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(20),
          children: [
            Text('Booking details', style: HouseholdType.title),
            const SizedBox(height: 12),
            HCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _detail('Booking ID', widget.booking['id'] as String? ?? '--'),
                _detail('Payment Ref', widget.booking['paystackRef'] as String? ?? '--'),
                _detail('Waste', Fmt.categoryLabel(widget.booking['wasteCategory'] as String?)),
                _detail('Weight', _weightLabel(widget.booking)),
                _detail('Collector', (widget.booking['collector'] as Map<String, dynamic>?)?['fullName'] as String? ?? '--'),
                _detail('Completed', Fmt.shortDate(widget.booking['completedAt'] as String? ?? widget.booking['updatedAt'] as String?)),
              ]),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              HCard(child: Text(_error!, style: HouseholdType.body.copyWith(color: HouseholdColors.danger))),
            const SizedBox(height: 12),
            HButton(label: 'Share PDF', icon: 'payment', onPressed: () => ReceiptService.shareReceipt(widget.booking)),
            const SizedBox(height: 10),
            HButton(
              label: 'Download PDF',
              icon: 'history',
              secondary: true,
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final file = await ReceiptService.createReceiptFile(widget.booking);
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(content: Text('Receipt saved to ${file.path}')),
                );
              },
            ),
            const SizedBox(height: 12),
            if (review == null)
              HButton(label: 'Rate collector', icon: 'star', onPressed: _submitting ? null : _submitReview)
            else
              HCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Your review', style: HouseholdType.section),
                  const SizedBox(height: 8),
                  Text('${review['rating'] ?? '--'} stars', style: HouseholdType.body),
                  if ((review['comment'] as String?)?.isNotEmpty == true)
                    Text(review['comment'] as String, style: HouseholdType.caption),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(width: 110, child: Text(label, style: HouseholdType.caption)),
          Expanded(child: Text(value, style: HouseholdType.body)),
        ]),
      );

  String _weightLabel(Map<String, dynamic> booking) {
    final weight = Fmt.toDouble(booking['actualWeightKg'] ?? booking['estimatedWeightKg']);
    return weight <= 0 ? '--' : '${weight.toStringAsFixed(1)} kg';
  }

  Future<void> _submitReview() async {
    final provider = context.read<HouseholdProvider>();
    final comment = TextEditingController();
    var rating = 5;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setState) => AlertDialog(
          title: Text('Rate collector', style: HouseholdType.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) => IconButton(
                      onPressed: () => setState(() => rating = i + 1),
                      icon: HIcon('star', size: 30, color: i < rating ? HouseholdColors.warning : HouseholdColors.gray),
                    )),
              ),
              TextField(
                controller: comment,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Comment'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Submit')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ApiClient.post('/api/bookings/${widget.booking['id']}/review', {
        'rating': rating,
        'comment': comment.text.trim(),
      });
      await provider.loadBookings();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not submit review.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
