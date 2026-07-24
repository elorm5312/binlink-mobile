import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/design_system/household_design_system.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/components/skeleton.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/household_provider.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _loading = true;
  String? _topUpReference;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<HouseholdProvider>().loadWalletSummary();
    } catch (_) {
      _error = 'Could not load wallet data.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final provider = context.watch<HouseholdProvider>();
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 116),
          children: [
            Text('Wallet', style: HouseholdType.hero),
            const SizedBox(height: 8),
            Text('Payments, eco points, rewards, coupons, and transactions.', style: HouseholdType.body.copyWith(color: HouseholdColors.gray)),
            const SizedBox(height: 22),
            HCard(
              color: HouseholdColors.forest,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Image.asset(HouseholdAssets.ecoPoints, height: 100),
                const SizedBox(height: 10),
                Text(Fmt.currency(provider.walletBalance), style: HouseholdType.hero.copyWith(color: Colors.white)),
                Text('Available balance', style: HouseholdType.caption.copyWith(color: Colors.white70)),
                const SizedBox(height: 14),
                HButton(label: 'Top up wallet', icon: 'wallet', secondary: true, onPressed: _showTopUpDialog),
                if (_topUpReference != null) ...[
                  const SizedBox(height: 12),
                  HButton(label: 'Verify top-up', icon: 'security', onPressed: () => _verifyTopUp(_topUpReference!)),
                ],
              ]),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _WalletTile(asset: HouseholdAssets.ecoPoints, title: 'Eco points', value: '${provider.ecoPoints} pts')),
              const SizedBox(width: 12),
              Expanded(child: _WalletTile(asset: HouseholdAssets.carbonSavings, title: 'Carbon saved', value: '${provider.carbonSavedKg.toStringAsFixed(1)} kg')),
            ]),
            const SizedBox(height: 16),
            if (_loading || provider.loadingWallet)
              const SkeletonList(count: 3)
            else if (_error != null || provider.walletError != null)
              HCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Wallet unavailable', style: HouseholdType.section.copyWith(color: HouseholdColors.danger)),
                const SizedBox(height: 8),
                Text(_error ?? provider.walletError!, style: HouseholdType.body),
                const SizedBox(height: 12),
                HButton(label: 'Retry', icon: 'recycle', secondary: true, onPressed: _load),
              ]))
            else ...[
              _Section(
                title: 'Pending transactions',
                emptyAsset: HouseholdAssets.noWallet,
                emptyText: 'No pending wallet activity.',
                items: provider.pendingTransactions,
              ),
              const SizedBox(height: 16),
              _Section(
                title: 'Recent transactions',
                emptyAsset: HouseholdAssets.noWallet,
                emptyText: 'No wallet activity yet.',
                items: provider.walletTransactions,
              ),
              const SizedBox(height: 16),
              HCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Available rewards', style: HouseholdType.section),
                const SizedBox(height: 12),
                if (provider.availableRewards.isEmpty)
                  Text('No rewards unlocked yet.', style: HouseholdType.body.copyWith(color: HouseholdColors.gray))
                else
                  ...provider.availableRewards.map((reward) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(children: [
                          HIcon('coupon', color: HouseholdColors.primary),
                          const SizedBox(width: 12),
                          Expanded(child: Text(reward.title, style: HouseholdType.body)),
                          Text('${reward.pointsRequired} pts', style: HouseholdType.caption.copyWith(color: reward.eligible ? HouseholdColors.ecoGreen : HouseholdColors.gray)),
                        ]),
                      )),
              ])),
              const SizedBox(height: 16),
              HCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Profile rewards', style: HouseholdType.section),
                const SizedBox(height: 12),
                Text(user?.fullName ?? 'BinLink household', style: HouseholdType.body),
                const SizedBox(height: 6),
                Text('${provider.rewardLedger.length} reward ledger entries', style: HouseholdType.caption),
              ])),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showTopUpDialog() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Top up wallet', style: HouseholdType.title),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount (GHS)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(dialogContext);
              final amount = double.tryParse(controller.text.trim());
              if (amount == null || amount <= 0) return;
              final data = await context.read<HouseholdProvider>().initializeWalletTopUp(amount);
              if (!mounted || data == null) return;
              final reference = data['reference'] as String?;
              final url = data['authorization_url'] as String?;
              if (reference != null) setState(() => _topUpReference = reference);
              navigator.pop();
              if (url != null) {
                final uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyTopUp(String reference) async {
    final ok = await context.read<HouseholdProvider>().verifyWalletTopUp(reference);
    if (!mounted) return;
    if (ok) {
      setState(() => _topUpReference = null);
      await _load();
    }
  }
}

class _WalletTile extends StatelessWidget {
  const _WalletTile({required this.asset, required this.title, required this.value});
  final String asset;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return HCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      asset.endsWith('.svg') ? SvgPicture.asset(asset, height: 76) : Image.asset(asset, height: 76, fit: BoxFit.contain),
      const SizedBox(height: 10),
      Text(title, style: HouseholdType.caption),
      Text(value, style: HouseholdType.section),
    ]));
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.emptyAsset,
    required this.emptyText,
    required this.items,
  });

  final String title;
  final String emptyAsset;
  final String emptyText;
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    return HCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: HouseholdType.section),
        const SizedBox(height: 16),
        if (items.isEmpty)
          Center(child: Column(children: [
            emptyAsset.endsWith('.svg') ? SvgPicture.asset(emptyAsset, height: 140) : Image.asset(emptyAsset, height: 140, fit: BoxFit.contain),
            Text(emptyText, style: HouseholdType.body.copyWith(color: HouseholdColors.gray)),
          ]))
        else
          ...items.take(8).map((tx) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  HIcon(_iconForType(tx['type'] as String? ?? ''), color: HouseholdColors.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tx['description'] as String? ?? (tx['type'] as String? ?? 'Transaction'), style: HouseholdType.body),
                    Text(tx['status'] as String? ?? '', style: HouseholdType.caption),
                  ])),
                  Text(Fmt.currency(((tx['amount'] as num?) ?? 0).toDouble()), style: HouseholdType.section),
                ]),
              )),
      ]),
    );
  }

  String _iconForType(String type) {
    if (type == 'REFUND') return 'history';
    if (type == 'DEBIT') return 'payment';
    return 'wallet';
  }
}
