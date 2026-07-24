import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../../core/design_system/collector_design_system.dart';
import '../../../core/utils/formatters.dart';
import '../providers/collector_provider.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});
  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<CollectorProvider>();
      p.loadDashboard();
      p.loadWallet();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CollectorProvider>();
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          await p.loadDashboard();
          await p.loadWallet();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 116),
          children: [
            Text('Wallet', style: CollectorType.hero),
            const SizedBox(height: 8),
            Text('Withdrawals, bonuses, fuel cost, commission, distance, and transaction history.', style: CollectorType.body.copyWith(color: const Color(0xFFC8D0DA))),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(color: CollectorColors.green, borderRadius: BorderRadius.circular(26)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CollectorAssets.wallet.endsWith('.svg') ? SvgPicture.asset(CollectorAssets.wallet, height: 110) : Image.asset(CollectorAssets.wallet, height: 110, fit: BoxFit.contain),
                Text(Fmt.currency(p.walletAvailable), style: CollectorType.hero.copyWith(color: CollectorColors.dark)),
                Text('Available balance', style: CollectorType.caption.copyWith(color: CollectorColors.dark.withAlpha(170))),
                const SizedBox(height: 18),
                CButton(label: 'WITHDRAW', icon: 'withdrawal', secondary: true, onPressed: p.walletAvailable > 0 ? () => _withdraw(context, p) : null),
              ]),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _Stat(asset: CollectorAssets.earningsBonus, label: 'Bonus', value: Fmt.currency(p.walletPending))),
              const SizedBox(width: 12),
              Expanded(child: _Stat(asset: CollectorAssets.earningsHistory, label: 'Withdrawn', value: Fmt.currency(p.walletWithdrawn))),
            ]),
            const SizedBox(height: 18),
            Text('Transactions', style: CollectorType.section),
            const SizedBox(height: 12),
            if (p.walletTransactions.isEmpty)
              CPanel(child: Column(children: [
                CollectorAssets.noTransactions.endsWith('.svg') ? SvgPicture.asset(CollectorAssets.noTransactions, height: 190) : Image.asset(CollectorAssets.noTransactions, height: 190, fit: BoxFit.contain),
                Text('No transactions yet', style: CollectorType.caption),
              ]))
            else
              ...p.walletTransactions.map((tx) {
                final isPayout = tx['type'] == 'PAYOUT';
                final color = isPayout ? CollectorColors.payout : CollectorColors.success;
                return CPanel(
                    child: Row(children: [
                      CIcon(isPayout ? 'withdrawal' : 'earnings', color: color),
                      const SizedBox(width: 12),
                      Expanded(child: Text(isPayout ? 'Payout' : 'Incoming earning', style: CollectorType.section)),
                      Text('${isPayout ? '-' : '+'}${Fmt.currency(Fmt.toDouble(tx['amount']))}', style: CollectorType.caption.copyWith(color: color, fontWeight: FontWeight.w900)),
                    ]),
                  );
              }),
          ],
        ),
      ),
    );
  }

  void _withdraw(BuildContext context, CollectorProvider p) {
    final phone = TextEditingController();
    final amount = TextEditingController(text: p.walletAvailable.toStringAsFixed(0));
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: CollectorColors.dark, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Withdraw funds', style: CollectorType.title),
            const SizedBox(height: 16),
            CTextField(
              controller: phone,
              label: 'Mobile money number',
              hint: '0XX XXX XXXX',
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
            ),
            const SizedBox(height: 12),
            CTextField(
              controller: amount,
              label: 'Amount',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 16),
            CButton(label: 'REQUEST WITHDRAWAL', onPressed: () async {
              final gross = double.tryParse(amount.text) ?? 0;
              await p.requestPayout(phone.text, gross, 'MTN');
              if (context.mounted) Navigator.maybePop(context);
            }),
          ]),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.asset, required this.label, required this.value});
  final String asset;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => CPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        asset.endsWith('.svg') ? SvgPicture.asset(asset, height: 86) : Image.asset(asset, height: 86, fit: BoxFit.contain),
        Text(label, style: CollectorType.caption),
        Text(value, style: CollectorType.section),
      ]));
}
