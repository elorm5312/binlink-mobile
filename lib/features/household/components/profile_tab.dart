import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/design_system/household_design_system.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../shared/components/binlink_avatar.dart';
import '../screens/favorites_screen.dart';
import '../screens/referral_screen.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 116),
        children: [
          Text('Profile', style: HouseholdType.hero),
          const SizedBox(height: 18),
          HCard(
            child: Row(children: [
              BinLinkAvatar(
                name: user?.fullName,
                imagePath: user?.profilePhoto,
                fallbackAsset: 'assets/household_assets/avatars/default_avatar.svg',
                size: 76,
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user?.fullName ?? 'BinLink household', style: HouseholdType.title),
                const SizedBox(height: 4),
                Text(user?.email ?? 'Manage your account and preferences', style: HouseholdType.caption),
              ])),
            ]),
          ),
          const SizedBox(height: 18),
          const _ProfileAction(icon: 'profile', label: 'Edit profile', route: '/edit-profile'),
          const _ProfileAction(icon: 'location', label: 'Saved addresses', route: '/saved-addresses'),
          _ProfileAction(
            icon: 'star',
            label: 'Favorite collectors',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesScreen())),
          ),
          _ProfileAction(
            icon: 'rewards',
            label: 'Invite & earn',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReferralScreen())),
          ),
          const _ProfileAction(icon: 'calendar', label: 'Subscriptions', route: '/subscriptions'),
          const _ProfileAction(icon: 'notifications', label: 'Notifications', route: '/notifications'),
          const _ProfileAction(icon: 'support', label: 'Help and FAQ', route: '/help'),
          const _ProfileAction(icon: 'privacy', label: 'Privacy', route: '/privacy'),
          const _ProfileAction(icon: 'security', label: 'Terms of Service', route: '/terms'),
          const _ProfileAction(icon: 'settings', label: 'Settings', route: '/settings'),
          _ProfileAction(icon: 'star', label: 'Rate app', onTap: () => _showRateDialog(context)),
          const SizedBox(height: 16),
          HButton(
            label: 'Sign out',
            icon: 'security',
            secondary: true,
            onPressed: () async {
              await context.read<AuthProvider>().signOut();
              if (context.mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
            },
          ),
        ],
      ),
    );
  }
}

void _showRateDialog(BuildContext context) {
  var rating = 0;
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: HouseholdColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: Text('Rate BinLink', style: HouseholdType.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('How was your pickup experience?', style: HouseholdType.body.copyWith(color: HouseholdColors.gray)),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final selected = i < rating;
                  return IconButton(
                    onPressed: () => setState(() => rating = i + 1),
                    icon: HIcon('star', size: 34, color: selected ? HouseholdColors.warning : HouseholdColors.border),
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.maybePop(dialogContext), child: Text('Not now', style: HouseholdType.body)),
            HButton(
              label: 'Submit rating',
              icon: 'star',
              onPressed: rating == 0
                  ? null
                  : () {
                      Navigator.maybePop(dialogContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Thanks for your feedback! 🙏'), duration: Duration(seconds: 3)),
                      );
                    },
            ),
          ],
        ),
      );
    },
  );
}

class _ProfileAction extends StatelessWidget {
  const _ProfileAction({required this.icon, required this.label, this.route, this.onTap});
  final String icon;
  final String label;
  final String? route;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: InkWell(
          onTap: onTap ?? () {
            final target = route;
            if (target != null) Navigator.pushNamed(context, target);
          },
          child: Row(children: [
            HIcon(icon, color: HouseholdColors.primary),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: HouseholdType.section)),
            HIcon('route', color: HouseholdColors.gray, size: 20),
          ]),
        ),
      ),
    );
  }
}
