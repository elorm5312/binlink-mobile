import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_flavor.dart';
import '../../core/network/api_client.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../models/user_model.dart';

/// Every user needs a phone number: it is how households and collectors reach
/// each other, and how BinLink contacts them. Collectors also give their number
/// plate and the expiry dates of their DVLA roadworthy certificate, insurance
/// and driver's licence. This full-screen page appears right after sign-in,
/// before booking and before going online, and cannot be skipped. The server
/// enforces the phone number too (no booking, no going online, no accepting
/// jobs without one).
class ProfileCompletion {
  static bool _showing = false;

  static bool _hasPhone(UserModel? u) => (u?.phone ?? '').trim().isNotEmpty;
  static bool _hasPlate(UserModel? u) => (u?.vehiclePlate ?? '').trim().isNotEmpty;
  static bool _hasDocs(UserModel? u) =>
      u?.roadworthyExpiry != null && u?.insuranceExpiry != null && u?.licenseExpiry != null;

  static bool isComplete(UserModel? u) =>
      _hasPhone(u) && (!FlavorConfig.isCollector || (_hasPlate(u) && _hasDocs(u)));

  /// Shows the page if details are missing. Returns true once complete.
  static Future<bool> ensure(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null || auth.user!.isAdmin || isComplete(auth.user)) return true;
    if (_showing) return false;
    _showing = true;
    try {
      await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => PopScope(canPop: false, child: CompleteProfileScreen(user: auth.user!)),
      ));
    } finally {
      _showing = false;
    }
    return context.mounted && isComplete(context.read<AuthProvider>().user);
  }
}

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key, required this.user});
  final UserModel user;

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  late final _phone = TextEditingController(text: widget.user.phone ?? '');
  late final _plate = TextEditingController(text: widget.user.vehiclePlate ?? '');
  late final _vehicle = TextEditingController(text: widget.user.vehicleType ?? '');
  late DateTime? _roadworthy = widget.user.roadworthyExpiry;
  late DateTime? _insurance = widget.user.insuranceExpiry;
  late DateTime? _license = widget.user.licenseExpiry;
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
    if (digits.length == 9 && !digits.startsWith('0')) return '0$digits';
    return null;
  }

  Future<void> _pickDate(DateTime? current, ValueChanged<DateTime> onPicked) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now.add(const Duration(days: 180)),
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 10),
      helpText: 'Select expiry date',
    );
    if (picked != null) setState(() => onPicked(picked));
  }

  Future<void> _save() async {
    final phone = _normalisePhone(_phone.text);
    final plate = _plate.text.trim().toUpperCase();
    if (phone == null) {
      setState(() => _error = 'Enter a valid Ghana phone number, e.g. 024 123 4567.');
      return;
    }
    if (_collector) {
      if (plate.length < 4) {
        setState(() => _error = 'Enter your vehicle number plate, e.g. GR 1234-24.');
        return;
      }
      if (_roadworthy == null || _insurance == null || _license == null) {
        setState(() => _error = 'Add the expiry dates for your DVLA roadworthy, insurance and driver\'s licence.');
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    String iso(DateTime d) => DateTime.utc(d.year, d.month, d.day).toIso8601String();
    try {
      final res = await ApiClient.patch('/api/profile', {
        'phone': phone,
        if (_collector) 'vehiclePlate': plate,
        if (_collector && _vehicle.text.trim().isNotEmpty) 'vehicleType': _vehicle.text.trim(),
        if (_collector) 'roadworthyExpiry': iso(_roadworthy!),
        if (_collector) 'insuranceExpiry': iso(_insurance!),
        if (_collector) 'licenseExpiry': iso(_license!),
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

  Future<void> _signOut() async {
    final nav = Navigator.of(context, rootNavigator: true);
    await context.read<AuthProvider>().signOut();
    nav.pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final dark = _collector;
    final bg = dark ? const Color(0xFF0B100D) : const Color(0xFFF4F7F4);
    final card = dark ? const Color(0xFF161D18) : Colors.white;
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

    Widget dateField(String label, IconData icon, DateTime? value, ValueChanged<DateTime> onPicked) {
      final expired = value != null && value.isBefore(DateTime.now());
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _pickDate(value, onPicked),
          child: InputDecorator(
            decoration: deco(label, '', icon).copyWith(
              suffixIcon: Icon(Icons.calendar_month_outlined, color: muted),
              helperText: expired ? 'Expired — renew it soon to keep taking jobs.' : null,
              helperStyle: const TextStyle(color: Color(0xFFF59E0B)),
            ),
            isEmpty: value == null,
            child: Text(
              value == null ? '' : DateFormat('d MMM yyyy').format(value),
              style: TextStyle(color: text, fontSize: 15),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _saving ? null : _signOut,
                child: Text('Sign out', style: TextStyle(color: muted)),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: accent.withAlpha(30), shape: BoxShape.circle),
                child: Icon(_collector ? Icons.badge_outlined : Icons.phone_iphone, color: accent, size: 36),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _collector ? 'Your contact & vehicle details' : 'Add your phone number',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 22, fontWeight: FontWeight.w800, color: text),
            ),
            const SizedBox(height: 8),
            Text(
              _collector
                  ? 'Households and BinLink use your phone number to reach you, and see your number plate for their safety. You need these before you can receive pickup requests.'
                  : 'Your collector and BinLink use this number to reach you about your pickups. You need it before you can request a pickup.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: muted, height: 1.45),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(20)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  autofocus: (widget.user.phone ?? '').isEmpty,
                  style: TextStyle(color: text),
                  decoration: deco('Phone number', '024 123 4567', Icons.phone_iphone),
                ),
                if (_collector) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _plate,
                    textCapitalization: TextCapitalization.characters,
                    style: TextStyle(color: text),
                    decoration: deco('Vehicle number plate', 'GR 1234-24', Icons.directions_car_filled_outlined),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _vehicle,
                    style: TextStyle(color: text),
                    decoration: deco('Vehicle type (optional)', 'Tricycle, pickup truck…', Icons.local_shipping_outlined),
                  ),
                  dateField('DVLA roadworthy expiry', Icons.fact_check_outlined, _roadworthy, (d) => _roadworthy = d),
                  dateField('Insurance expiry', Icons.shield_outlined, _insurance, (d) => _insurance = d),
                  dateField('Driver\'s licence expiry', Icons.credit_card_outlined, _license, (d) => _license = d),
                ],
              ]),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 54,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: dark ? const Color(0xFF0B100D) : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save and continue', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
