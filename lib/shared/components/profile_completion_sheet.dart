import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_flavor.dart';
import '../../core/network/api_client.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../models/user_model.dart';

/// Every user needs a phone number (collectors and households call each other
/// from the tracking screens) and every collector needs a number plate (shown
/// to households for safety). This sheet collects whatever is missing and
/// cannot be dismissed until it is saved.
class ProfileCompletion {
  static bool _showing = false;

  static bool _hasPhone(UserModel? u) => (u?.phone ?? '').trim().isNotEmpty;
  static bool _hasPlate(UserModel? u) => (u?.vehiclePlate ?? '').trim().isNotEmpty;

  static bool isComplete(UserModel? u) =>
      _hasPhone(u) && (!FlavorConfig.isCollector || _hasPlate(u));

  /// Shows the sheet if details are missing. Returns true once complete.
  static Future<bool> ensure(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null || auth.user!.isAdmin || isComplete(auth.user)) return true;
    if (_showing) return false;
    _showing = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (_) => PopScope(canPop: false, child: _ProfileCompletionSheet(user: auth.user!)),
      );
    } finally {
      _showing = false;
    }
    return context.mounted && isComplete(context.read<AuthProvider>().user);
  }
}

class _ProfileCompletionSheet extends StatefulWidget {
  const _ProfileCompletionSheet({required this.user});
  final UserModel user;

  @override
  State<_ProfileCompletionSheet> createState() => _ProfileCompletionSheetState();
}

class _ProfileCompletionSheetState extends State<_ProfileCompletionSheet> {
  late final _phone = TextEditingController(text: widget.user.phone ?? '');
  late final _plate = TextEditingController(text: widget.user.vehiclePlate ?? '');
  late final _vehicle = TextEditingController(text: widget.user.vehicleType ?? '');
  bool _saving = false;
  String? _error;

  bool get _collector => FlavorConfig.isCollector;

  @override
  void dispose() {
    _phone.dispose();
    _plate.dispose();
    _vehicle.dispose();
    super.dispose();
  }

  /// Ghana numbers: 0XXXXXXXXX, 233XXXXXXXXX or +233XXXXXXXXX → 0XXXXXXXXX.
  String? _normalisePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10 && digits.startsWith('0')) return digits;
    if (digits.length == 12 && digits.startsWith('233')) return '0${digits.substring(3)}';
    if (digits.length == 9) return '0$digits';
    return null;
  }

  Future<void> _save() async {
    final phone = _normalisePhone(_phone.text);
    final plate = _plate.text.trim().toUpperCase();
    if (phone == null) {
      setState(() => _error = 'Enter a valid Ghana phone number, e.g. 024 123 4567.');
      return;
    }
    if (_collector && plate.length < 4) {
      setState(() => _error = 'Enter your vehicle number plate, e.g. GR 1234-24.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await ApiClient.patch('/api/profile', {
        'phone': phone,
        if (_collector) 'vehiclePlate': plate,
        if (_collector && _vehicle.text.trim().isNotEmpty) 'vehicleType': _vehicle.text.trim(),
      });
      final data = res.data['data'];
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      if (data is Map) {
        auth.updateUser(UserModel.fromJson(Map<String, dynamic>.from(data)));
      } else {
        await auth.refreshProfile();
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = ApiClient.messageFrom(e) ?? 'Could not save your details. Check your connection and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = _collector;
    final bg = dark ? const Color(0xFF161D18) : Colors.white;
    final text = dark ? Colors.white : const Color(0xFF0B3B2E);
    final muted = dark ? const Color(0xFF9AA8A0) : const Color(0xFF6B7280);
    final accent = dark ? const Color(0xFF2BD97B) : const Color(0xFF16A34A);
    final fieldFill = dark ? const Color(0xFF0B100D) : const Color(0xFFF4F7F4);

    InputDecoration deco(String label, String hint, IconData icon) => InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: accent),
          labelStyle: TextStyle(color: muted),
          hintStyle: TextStyle(color: muted.withAlpha(150)),
          filled: true,
          fillColor: fieldFill,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
        padding: EdgeInsets.fromLTRB(22, 22, 22, MediaQuery.paddingOf(context).bottom + 22),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Icon(Icons.verified_user_outlined, color: accent, size: 40),
          const SizedBox(height: 12),
          Text('Complete your profile',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 20, fontWeight: FontWeight.w800, color: text)),
          const SizedBox(height: 6),
          Text(
            _collector
                ? 'Households see your phone number and number plate for their safety, and call you if needed. Add them to start taking jobs.'
                : 'Your collector needs your phone number to reach you about your pickup. Add it to start booking.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: muted, height: 1.4),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            style: TextStyle(color: text),
            decoration: deco('Phone number', '024 123 4567', Icons.phone_iphone),
          ),
          if (_collector) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _plate,
              textCapitalization: TextCapitalization.characters,
              style: TextStyle(color: text),
              decoration: deco('Number plate', 'GR 1234-24', Icons.directions_car_filled_outlined),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _vehicle,
              style: TextStyle(color: text),
              decoration: deco('Vehicle type (optional)', 'Tricycle, pickup truck…', Icons.local_shipping_outlined),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: dark ? const Color(0xFF0B100D) : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
              ),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save and continue', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ]),
      ),
    );
  }
}
