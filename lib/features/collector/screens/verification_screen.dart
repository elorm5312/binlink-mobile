import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../core/design_system/collector_design_system.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/collector_provider.dart';

/// Collector KYC / verification. Capture Ghana Card, driver's license and a
/// vehicle photo, submit for admin review. Gates going online until approved.
class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final _picker = ImagePicker();
  final _ghanaCardNo = TextEditingController();
  final _licenseNo = TextEditingController();
  final _docs = <String, String>{}; // field -> local path
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ghanaCardNo.dispose();
    _licenseNo.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await context.read<CollectorProvider>().loadKyc();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _capture(String field) async {
    final img = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 1600);
    if (img != null && mounted) setState(() => _docs[field] = img.path);
  }

  Future<void> _submit() async {
    if (_docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one document photo')));
      return;
    }
    setState(() => _submitting = true);
    final err = await context.read<CollectorProvider>().submitKyc(
      files: _docs,
      ghanaCardNumber: _ghanaCardNo.text.trim(),
      licenseNumber: _licenseNo.text.trim(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (err == null) {
      await context.read<AuthProvider>().refreshProfile();
      if (mounted) setState(() {});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<CollectorProvider>();
    return Scaffold(
      backgroundColor: CollectorColors.dark,
      appBar: AppBar(
        backgroundColor: CollectorColors.dark,
        foregroundColor: CollectorColors.white,
        elevation: 0,
        title: Text('Verification', style: CollectorType.title),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: CollectorColors.green))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _content(prov),
            ),
    );
  }

  Widget _content(CollectorProvider prov) {
    final status = prov.kycStatus; // NONE | PENDING | APPROVED | REJECTED
    if (prov.isVerified || status == 'APPROVED') {
      return _StatusCard(
        icon: PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
        color: CollectorColors.success,
        title: 'You\'re verified',
        body: 'Your account is approved. Head back and tap GO to start receiving pickups.',
      );
    }
    if (status == 'PENDING') {
      return _StatusCard(
        icon: PhosphorIcons.clock(PhosphorIconsStyle.fill),
        color: CollectorColors.warning,
        title: 'Under review',
        body: 'Your documents were submitted and are being reviewed. You\'ll be notified once approved (usually within 24 hours).',
      );
    }

    // NONE or REJECTED â†’ show the upload form.
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (status == 'REJECTED')
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: CollectorColors.red.withAlpha(30),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: CollectorColors.red.withAlpha(120)),
          ),
          child: Row(children: [
            Icon(PhosphorIcons.warning(PhosphorIconsStyle.fill), color: CollectorColors.red, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(
              prov.kycRejectionReason ?? 'Your documents were not approved. Please re-submit.',
              style: CollectorType.caption.copyWith(color: CollectorColors.white))),
          ]),
        ),
      Text('Verify your account', style: CollectorType.title),
      const SizedBox(height: 6),
      Text('We vet every collector for safety. Upload clear photos of your documents.',
          style: CollectorType.caption),
      const SizedBox(height: 20),
      _DocTile(label: 'Ghana Card', field: 'ghanaCard', path: _docs['ghanaCard'], onTap: () => _capture('ghanaCard')),
      const SizedBox(height: 10),
      CTextField(controller: _ghanaCardNo, label: 'Ghana Card number', hint: 'GHA-XXXXXXXXX-X'),
      const SizedBox(height: 18),
      _DocTile(label: 'Driver\'s License', field: 'license', path: _docs['license'], onTap: () => _capture('license')),
      const SizedBox(height: 10),
      CTextField(controller: _licenseNo, label: 'License number'),
      const SizedBox(height: 18),
      _DocTile(label: 'Vehicle photo', field: 'vehiclePhoto', path: _docs['vehiclePhoto'], onTap: () => _capture('vehiclePhoto')),
      const SizedBox(height: 26),
      CButton(
        label: status == 'REJECTED' ? 'Re-submit for review' : 'Submit for review',
        icon: 'navigation',
        loading: _submitting,
        onPressed: _submitting ? null : _submit,
      ),
      const SizedBox(height: 12),
    ]);
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({required this.label, required this.field, required this.path, required this.onTap});
  final String label;
  final String field;
  final String? path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final has = path != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: CollectorColors.charcoal,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: has ? CollectorColors.green : CollectorColors.line, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: has
            ? Stack(fit: StackFit.expand, children: [
                Image.file(File(path!), fit: BoxFit.cover),
                Positioned(top: 8, right: 8, child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: CollectorColors.green, shape: BoxShape.circle),
                  child: Icon(PhosphorIcons.check(PhosphorIconsStyle.bold), size: 14, color: Colors.white),
                )),
                Positioned(bottom: 8, left: 10, child: Text(label,
                    style: CollectorType.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w700))),
              ])
            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(PhosphorIcons.camera(), color: CollectorColors.green, size: 28),
                const SizedBox(height: 8),
                Text('Tap to photograph $label', style: CollectorType.caption),
              ]),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.icon, required this.color, required this.title, required this.body});
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return CPanel(
      child: Column(children: [
        const SizedBox(height: 10),
        Icon(icon, size: 64, color: color),
        const SizedBox(height: 16),
        Text(title, style: CollectorType.title, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(body, style: CollectorType.caption, textAlign: TextAlign.center),
        const SizedBox(height: 10),
      ]),
    );
  }
}
