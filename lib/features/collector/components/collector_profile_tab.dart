import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/design_system/collector_design_system.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../shared/components/binlink_avatar.dart';

class CollectorProfileTab extends StatelessWidget {
  const CollectorProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 116),
        children: [
          Text('Profile', style: CollectorType.hero),
          const SizedBox(height: 18),
          CPanel(
            child: Row(children: [
              BinLinkAvatar(
                name: user?.fullName,
                imagePath: user?.profilePhoto,
                fallbackAsset: 'assets/collector_assets/avatars/default_avatar.svg',
                size: 82,
                dark: true,
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user?.fullName ?? 'BinLink Eco collector', style: CollectorType.title),
                const SizedBox(height: 4),
                Text('${user?.vehiclePlate ?? 'Vehicle pending'} • ${user?.rating.toStringAsFixed(1) ?? '5.0'} rating', style: CollectorType.caption),
              ])),
            ]),
          ),
          const SizedBox(height: 16),
          const _Action(icon: 'profile', label: 'Edit profile', route: '/collector-profile-edit'),
          const _Action(icon: 'truck', label: 'Vehicle', route: '/collector-vehicle'),
          const _Action(icon: 'reviews', label: 'Reviews', route: '/collector-reviews'),
          const _Action(icon: 'rating', label: 'Ratings', route: '/collector-ratings'),
          const _Action(icon: 'history', label: 'History', route: '/collector-jobs'),
          const _Action(icon: 'settings', label: 'Settings', route: '/collector-settings'),
          const _Action(icon: 'support', label: 'Support', route: '/collector-support'),
          const _Action(icon: 'privacy', label: 'Privacy', route: '/collector-privacy'),
          const SizedBox(height: 16),
          CButton(label: 'SIGN OUT', icon: 'security', secondary: true, onPressed: () async {
            await auth.signOut();
            if (context.mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
          }),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.route});
  final String icon;
  final String label;
  final String route;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => Navigator.pushNamed(context, route),
        child: CPanel(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(children: [
            CIcon(icon, color: CollectorColors.green),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: CollectorType.section)),
            const CIcon('navigation', color: Color(0xFF95A1B2), size: 20),
          ]),
        ),
      ),
    );
  }
}
