import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/design_system/household_design_system.dart';
import '../providers/household_provider.dart';

/// Referral program — share a code, both sides earn wallet credit.
class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = true;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() { _codeCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    await context.read<HouseholdProvider>().loadReferral();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _apply() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty || _applying) return;
    setState(() => _applying = true);
    final err = await context.read<HouseholdProvider>().applyReferralCode(code);
    if (!mounted) return;
    setState(() => _applying = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: err == null ? HouseholdColors.ecoGreen : HouseholdColors.danger,
      content: Text(err ?? 'Referral applied — wallet credited!')));
  }

  @override
  Widget build(BuildContext context) {
    final ref = context.watch<HouseholdProvider>().referral;
    final code = ref?['code'] as String? ?? '------';
    final bonus = ((ref?['bonus'] as num?) ?? 5).toDouble();
    final referred = ((ref?['referredCount'] as num?) ?? 0).toInt();
    final hasReferrer = ref?['hasReferrer'] == true;

    return Scaffold(
      backgroundColor: HouseholdColors.sand,
      appBar: AppBar(
        backgroundColor: HouseholdColors.sand,
        elevation: 0,
        foregroundColor: HouseholdColors.forest,
        title: Text('Invite & earn', style: HouseholdType.title),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: HouseholdColors.primary))
          : ListView(padding: const EdgeInsets.all(20), children: [
              HCard(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  Icon(PhosphorIcons.gift(PhosphorIconsStyle.fill), size: 44, color: HouseholdColors.primary),
                  const SizedBox(height: 12),
                  Text('Give GHS ${bonus.toStringAsFixed(0)}, get GHS ${bonus.toStringAsFixed(0)}',
                      style: HouseholdType.title, textAlign: TextAlign.center),
                  const SizedBox(height: 6),
                  Text('Share your code. When a friend signs up and uses it, you both get GHS ${bonus.toStringAsFixed(0)} in your wallet.',
                      style: HouseholdType.caption.copyWith(color: HouseholdColors.gray), textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied')));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: HouseholdColors.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: HouseholdColors.primary.withAlpha(80), style: BorderStyle.solid),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(code, style: HouseholdType.number.copyWith(
                            color: HouseholdColors.primary, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 4)),
                        const SizedBox(width: 10),
                        Icon(PhosphorIcons.copy(), size: 20, color: HouseholdColors.primary),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 16),
                  HButton(
                    label: 'Share invite',
                    icon: 'rewards',
                    onPressed: () => Share.share(
                        'Join me on BinLink for waste pickups! Use my code $code when you sign up and we both get GHS ${bonus.toStringAsFixed(0)} free. https://binlink.eco'),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              HCard(
                child: Row(children: [
                  HIcon('profile', color: HouseholdColors.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Friends referred', style: HouseholdType.section)),
                  Text('$referred', style: HouseholdType.number.copyWith(
                      color: HouseholdColors.primary, fontSize: 22, fontWeight: FontWeight.w800)),
                ]),
              ),
              const SizedBox(height: 14),
              if (!hasReferrer)
                HCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Have a referral code?', style: HouseholdType.section),
                    const SizedBox(height: 4),
                    Text('Enter a friend\'s code to claim your welcome bonus.',
                        style: HouseholdType.caption.copyWith(color: HouseholdColors.gray)),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: HTextField(controller: _codeCtrl, label: 'Referral code')),
                      const SizedBox(width: 10),
                      SizedBox(height: 52, child: FilledButton(
                        onPressed: _applying ? null : _apply,
                        style: FilledButton.styleFrom(backgroundColor: HouseholdColors.primary),
                        child: _applying
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Apply'),
                      )),
                    ]),
                  ]),
                )
              else
                HCard(child: Row(children: [
                  Icon(PhosphorIcons.checkCircle(PhosphorIconsStyle.fill), color: HouseholdColors.ecoGreen, size: 22),
                  const SizedBox(width: 10),
                  Expanded(child: Text('You\'ve already claimed a referral bonus.',
                      style: HouseholdType.caption.copyWith(color: HouseholdColors.gray))),
                ])),
            ]),
    );
  }
}
