import 'package:flutter/material.dart';

/// Bookings that were completed but not yet paid (newest first).
List<Map<String, dynamic>> unpaidCompleted(Iterable<Map<String, dynamic>> bookings) {
  final cutoff = DateTime.now().subtract(const Duration(days: 7));
  final list = bookings.where((b) {
    if (!const ['COMPLETED', 'COLLECTED'].contains(b['status'])) return false;
    if (b['paymentStatus'] == 'PAID') return false;
    final done = DateTime.tryParse('${b['completedAt'] ?? b['updatedAt'] ?? ''}');
    return done == null || done.isAfter(cutoff);
  }).toList()
    ..sort((a, b) => '${b['completedAt'] ?? ''}'.compareTo('${a['completedAt'] ?? ''}'));
  return list;
}

/// Pins a banner above [child] (all tabs) and removes the top safe-area inset
/// from [child] so screens that position content under the status bar do not
/// leave a double gap.
class TopBannerScaffoldBody extends StatelessWidget {
  const TopBannerScaffoldBody({super.key, required this.banner, required this.child});
  final Widget? banner;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (banner == null) return child;
    return Column(children: [
      SafeArea(bottom: false, child: banner!),
      Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: child)),
    ]);
  }
}

/// "Payment pending" strip shown at the top of the app.
class PendingPaymentBanner extends StatelessWidget {
  const PendingPaymentBanner({
    super.key,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
    required this.background,
    required this.foreground,
    required this.accent,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;
  final Color background;
  final Color foreground;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(children: [
            Icon(Icons.payments_rounded, color: accent, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title,
                    style: TextStyle(fontFamily: 'PlusJakartaSans', fontWeight: FontWeight.w800, fontSize: 14, color: foreground)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 12, color: foreground.withAlpha(200))),
              ]),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: background,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                minimumSize: const Size(0, 36),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              onPressed: onTap,
              child: Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            ),
          ]),
        ),
      ),
    );
  }
}
