import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/design_system/household_design_system.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/receipt_service.dart';
import '../../../core/storage/secure_storage.dart';
import '../providers/household_provider.dart';
import 'tracking_screen.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, this.booking = const {}});
  final Map<String, dynamic> booking;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> with WidgetsBindingObserver {
  String _method = 'mtn_momo';
  bool _loading = false;
  bool _verifying = false;
  String? _error;
  String? _successRef;
  String? _reference;
  bool _awaitingVerification = false;
  Map<String, dynamic>? _verifiedBooking;
  final _phoneCtrl = TextEditingController();
  String? _promptText; // "Approve the prompt on your phone…" while charging MoMo
  bool _polling = false;
  bool _cancelPolling = false;

  static const _momoMethods = {'mtn_momo', 'telecel_cash', 'airteltigo_money'};
  bool get _isMomo => _momoMethods.contains(_method);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    context.read<HouseholdProvider>().loadWalletSummary();
    SecureStorage.getUser().then((user) {
      final userPhone = user?['phone'] as String?;
      if (userPhone != null && userPhone.isNotEmpty && _phoneCtrl.text.isEmpty) {
        _phoneCtrl.text = userPhone;
      }
    });
  }

  @override
  void dispose() {
    _cancelPolling = true;
    _phoneCtrl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only the legacy redirect flow needs resume-based verification. The direct
    // MoMo charge polls verify itself, so skip re-verifying on resume for it.
    if (state == AppLifecycleState.resumed &&
        _awaitingVerification &&
        !_isMomo &&
        _reference != null &&
        widget.booking['id'] is String) {
      _verifyPayment(widget.booking['id'] as String, _reference!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = widget.booking['totalAmount'];
    final bookingId = widget.booking['id'] as String?;
    final walletBalance = context.watch<HouseholdProvider>().walletBalance;
    final amountValue = (amount as num?)?.toDouble() ?? double.tryParse('$amount') ?? 0;
    return Scaffold(
      backgroundColor: HouseholdColors.sand,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(children: [
              IconButton(onPressed: () => Navigator.maybePop(context), icon: HIcon('route', color: HouseholdColors.forest)),
              const SizedBox(width: 8),
              Text('Payment', style: HouseholdType.title),
            ]),
            const SizedBox(height: 12),
            HCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Image.asset(HouseholdAssets.ecoPoints, height: 100),
                const SizedBox(height: 12),
                Text(amount == null ? 'Amount pending' : 'GHS $amount', style: HouseholdType.hero),
                Text(widget.booking['pickupAddress'] as String? ?? 'Pickup payment', style: HouseholdType.caption),
              ]),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              HCard(color: HouseholdColors.dangerTint, child: Text(_error!, style: HouseholdType.body.copyWith(color: HouseholdColors.danger))),
            ],
            if (_successRef != null) ...[
              const SizedBox(height: 12),
              HCard(color: const Color(0xFFEFFBF4), child: Row(children: [
                Lottie.asset('assets/household_assets/lottie/success.json', width: 64, height: 64),
                const SizedBox(width: 12),
                Expanded(child: Text('Payment initialized: $_successRef', style: HouseholdType.body.copyWith(color: HouseholdColors.ecoGreen))),
              ])),
            ],
            if (_promptText != null) ...[
              const SizedBox(height: 12),
              HCard(color: HouseholdColors.infoTint, child: Row(children: [
                if (_polling)
                  const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  HIcon('security', color: HouseholdColors.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(_promptText!, style: HouseholdType.body.copyWith(color: HouseholdColors.charcoal))),
              ])),
            ],
            // Manual "Verify payment" fallback (legacy redirect flow only).
            if (_reference != null && !_isMomo && !_verifying) ...[
              const SizedBox(height: 12),
              HButton(label: 'Verify payment', icon: 'security', onPressed: bookingId == null ? null : () => _verifyPayment(bookingId, _reference!)),
            ],
            const SizedBox(height: 18),
            Text('Payment method', style: HouseholdType.section),
            const SizedBox(height: 12),
            for (final method in const [
              ('mtn_momo', 'MTN MoMo'),
              ('telecel_cash', 'Telecel Cash'),
              ('airteltigo_money', 'AirtelTigo Money'),
              ('cash', 'Cash'),
              ('wallet', 'Wallet'),
            ])
              _PaymentMethod(id: method.$1, label: method.$2, selected: _method == method.$1, onTap: () => setState(() => _method = method.$1)),
            if (_isMomo) ...[
              const SizedBox(height: 4),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                style: HouseholdType.body.copyWith(color: HouseholdColors.charcoal),
                decoration: InputDecoration(
                  labelText: 'Mobile money number',
                  hintText: '024 123 4567',
                  prefixIcon: Icon(Icons.phone_iphone, color: HouseholdColors.primary),
                  filled: true,
                  fillColor: HouseholdColors.card,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 6),
              Text('You will get a prompt on this number to approve the payment.',
                  style: HouseholdType.caption),
            ],
            if (_method == 'wallet') ...[
              const SizedBox(height: 12),
              HCard(
                color: walletBalance < amountValue ? HouseholdColors.dangerTint : HouseholdColors.card,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Wallet balance', style: HouseholdType.section),
                    const SizedBox(height: 6),
                    Text('GHS ${walletBalance.toStringAsFixed(2)}', style: HouseholdType.body),
                    if (walletBalance < amountValue) ...[
                      const SizedBox(height: 8),
                      Text('Insufficient balance', style: HouseholdType.caption.copyWith(color: HouseholdColors.danger)),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            HButton(
              label: _method == 'cash'
                  ? 'Confirm cash payment'
                  : _isMomo
                      ? 'Pay with mobile money'
                      : _method == 'wallet'
                          ? 'Pay from wallet'
                          : 'Initialize secure payment',
              icon: 'payment',
              loading: _loading || _polling,
              onPressed: bookingId == null || _polling || (_method == 'wallet' && walletBalance < amountValue)
                  ? null
                  : () => _confirmPayment(bookingId),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmPayment(String bookingId) async {
    setState(() {
      _loading = true;
      _error = null;
      _successRef = null;
    });
    try {
      if (_method == 'cash') {
        setState(() => _successRef = 'Cash payment is recorded on collection.');
        if (bookingId.isNotEmpty) {
          await _finishPayment(bookingId);
        }
        return;
      }
      if (_method == 'wallet') {
        await _verifyPayment(bookingId, 'wallet:$bookingId', method: 'wallet');
        return;
      }
      if (_isMomo) {
        await _chargeMomo(bookingId);
        return;
      }
      final res = await ApiClient.post('/api/payments/initialize', {'bookingId': bookingId});
      final data = Map<String, dynamic>.from(res.data['data'] as Map);
      final ref = data['reference'] as String?;
      final url = data['authorization_url'] as String?;
      setState(() {
        _successRef = ref ?? 'Pending';
        _reference = ref;
        _awaitingVerification = ref != null;
      });
      if (url != null && url.isNotEmpty) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      setState(() => _error = 'Payment could not be initialized. Please check your connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Direct Ghana mobile-money charge: sends an approval prompt to the user's
  /// phone, then polls the backend until the charge is confirmed.
  Future<void> _chargeMomo(String bookingId) async {
    final phone = _phoneCtrl.text.trim();
    if (phone.length < 9) {
      setState(() => _error = 'Enter a valid mobile money number.');
      return;
    }
    try {
      final res = await ApiClient.post('/api/payments/charge', {
        'bookingId': bookingId,
        'phone': phone,
        'method': _method,
      });
      final data = Map<String, dynamic>.from(res.data['data'] as Map? ?? {});
      final ref = data['reference'] as String?;
      final status = data['status'] as String?;
      setState(() {
        _reference = ref;
        _promptText = (data['displayText'] as String?) ??
            'Approve the payment prompt on your phone to complete the charge.';
      });
      if (status == 'success') {
        // Already approved (e.g. sandbox) — finalize immediately.
        await _verifyPayment(bookingId, ref ?? '', method: 'momo');
        return;
      }
      if (ref != null) {
        await _pollVerification(bookingId, ref);
      }
    } catch (e) {
      setState(() {
        _error = ApiClient.messageFrom(e) ?? 'Could not start the mobile money charge. Please try again.';
        _promptText = null;
      });
    }
  }

  /// Polls /api/payments/verify until the booking is PAID or the window closes.
  /// The verify endpoint returns 4xx while the charge is still pending, so we
  /// swallow those and keep polling.
  Future<void> _pollVerification(String bookingId, String reference) async {
    if (_polling) return;
    setState(() {
      _polling = true;
      _cancelPolling = false;
    });
    const attempts = 24; // ~2 min at 5s spacing
    for (var i = 0; i < attempts; i++) {
      if (_cancelPolling || !mounted) return;
      await Future.delayed(const Duration(seconds: 5));
      if (_cancelPolling || !mounted) return;
      try {
        await ApiClient.post('/api/payments/verify', {'bookingId': bookingId, 'reference': reference});
        // 200 → payment confirmed.
        if (mounted) setState(() => _polling = false);
        await _verifyPayment(bookingId, reference, method: 'momo');
        return;
      } catch (_) {
        // Still pending — keep waiting.
      }
    }
    if (mounted) {
      setState(() {
        _polling = false;
        _promptText = null;
        _error = 'We didn\'t get a confirmation in time. If you approved the prompt, tap Pay again to retry.';
      });
    }
  }

  Future<void> _verifyPayment(String bookingId, String reference, {String? method}) async {
    if (_verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final provider = context.read<HouseholdProvider>();
      await ApiClient.post('/api/payments/verify', {
        'bookingId': bookingId,
        if (method != null) 'method': method,
        if (method != 'wallet') 'reference': reference,
      });
      await provider.loadBookings();
      await provider.loadWalletSummary();
      final refreshedBooking = provider.bookings.cast<Map<String, dynamic>?>().firstWhere(
            (booking) => booking?['id'] == bookingId,
            orElse: () => widget.booking,
          ) ??
          widget.booking;
      _verifiedBooking = Map<String, dynamic>.from(refreshedBooking);
      await ReceiptService.shareReceipt(_verifiedBooking!);
      if (!mounted) return;
      setState(() {
        _awaitingVerification = false;
        _successRef = 'Payment verified';
      });
      HapticFeedback.lightImpact();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PaymentSuccessScreen(
            booking: _verifiedBooking!,
            reference: reference,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Payment verification failed. Please retry after the callback returns.');
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _finishPayment(String bookingId) async {
    final provider = context.read<HouseholdProvider>();
    await provider.loadBookings();
    final booking = provider.bookings.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item?['id'] == bookingId,
          orElse: () => widget.booking,
        ) ??
        widget.booking;
    _verifiedBooking = Map<String, dynamic>.from(booking);
    await ReceiptService.shareReceipt(_verifiedBooking!);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PaymentSuccessScreen(
          booking: _verifiedBooking!,
          reference: _reference,
        ),
      ),
    );
  }
}

class PaymentSuccessScreen extends StatelessWidget {
  const PaymentSuccessScreen({
    super.key,
    required this.booking,
    this.reference,
  });

  final Map<String, dynamic> booking;
  final String? reference;

  @override
  Widget build(BuildContext context) {
    final amount = booking['totalAmount'];
    final status = booking['status'] as String? ?? 'PENDING';
    return Scaffold(
      backgroundColor: HouseholdColors.sand,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            HCard(
              child: Column(
                children: [
                  Lottie.asset(
                    'assets/household_assets/lottie/success.json',
                    width: 160,
                    height: 160,
                    repeat: false,
                  ),
                  const SizedBox(height: 8),
                  Text('Payment confirmed', style: HouseholdType.hero, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    'Your booking is synced with BinLink and ready for live tracking.',
                    style: HouseholdType.body.copyWith(color: HouseholdColors.gray),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            HCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SuccessRow(label: 'Booking ID', value: booking['id'] as String? ?? '--'),
                  const SizedBox(height: 10),
                  _SuccessRow(label: 'Status', value: status),
                  const SizedBox(height: 10),
                  _SuccessRow(label: 'Amount', value: amount == null ? '--' : 'GHS $amount'),
                  if (reference != null) ...[
                    const SizedBox(height: 10),
                    _SuccessRow(label: 'Reference', value: reference!),
                  ],
                  if ((booking['pickupAddress'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 10),
                    _SuccessRow(label: 'Pickup address', value: booking['pickupAddress'] as String),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            HButton(
              label: 'Share receipt',
              icon: 'payment',
              onPressed: () => ReceiptService.shareReceipt(booking),
            ),
            const SizedBox(height: 12),
            HButton(
              label: 'Track booking',
              icon: 'tracking',
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => TrackingScreen(booking: booking)),
              ),
            ),
            const SizedBox(height: 12),
            HButton(
              label: 'Back to home',
              icon: 'home',
              secondary: true,
              onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/household', (_) => false),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessRow extends StatelessWidget {
  const _SuccessRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 108,
          child: Text(label, style: HouseholdType.caption),
        ),
        Expanded(child: Text(value, style: HouseholdType.section)),
      ],
    );
  }
}

// PNG for MoMo networks, SVG fallback for generic methods
class _PaymentLogo extends StatelessWidget {
  const _PaymentLogo({required this.id});
  final String id;
  static const _hasPng = {'mtn_momo', 'telecel_cash', 'airteltigo_money'};

  @override
  Widget build(BuildContext context) {
    if (_hasPng.contains(id)) {
      return Image.asset('assets/household_assets/payments/$id.png', width: 82, height: 42, fit: BoxFit.contain);
    }
    return SvgPicture.asset('assets/household_assets/payments/$id.svg', width: 82, height: 42);
  }
}

class _PaymentMethod extends StatelessWidget {
  const _PaymentMethod({required this.id, required this.label, required this.selected, required this.onTap});
  final String id;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: HCard(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            _PaymentLogo(id: id),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: HouseholdType.section)),
            if (selected) HIcon('security', color: HouseholdColors.primary),
          ]),
        ),
      ),
    );
  }
}
