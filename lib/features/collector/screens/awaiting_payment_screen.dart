import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/design_system/collector_design_system.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/socket_service.dart';
import '../../../core/utils/json_num.dart';

/// Shown to the collector right after completing a pickup: waits until the
/// household pays (live 'booking:paid' event, with polling as a backup) and
/// confirms it before the collector leaves.
class AwaitingPaymentScreen extends StatefulWidget {
  const AwaitingPaymentScreen({super.key, required this.bookingId, this.amount});
  final String bookingId;
  final double? amount;

  @override
  State<AwaitingPaymentScreen> createState() => _AwaitingPaymentScreenState();
}

class _AwaitingPaymentScreenState extends State<AwaitingPaymentScreen> {
  bool _paid = false;
  double? _amount;
  Timer? _poll;
  late final void Function(dynamic) _onPaid;

  @override
  void initState() {
    super.initState();
    _amount = widget.amount;
    _onPaid = (data) {
      if (data is Map && data['bookingId'] == widget.bookingId) {
        _markPaid(jsonDouble(data['amount']));
      }
    };
    SocketService.joinBookingRoom(widget.bookingId);
    SocketService.on('booking:paid', _onPaid);
    _check();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    SocketService.offHandler('booking:paid', _onPaid);
    super.dispose();
  }

  Future<void> _check() async {
    if (_paid) return;
    try {
      final res = await ApiClient.get('/api/bookings/${widget.bookingId}');
      final b = Map<String, dynamic>.from(res.data['data'] as Map);
      final amount = jsonDouble(b['totalAmount']);
      if (!mounted) return;
      if (b['paymentStatus'] == 'PAID') {
        _markPaid(amount);
      } else if (amount != null && amount != _amount) {
        setState(() => _amount = amount);
      }
    } catch (_) {}
  }

  void _markPaid(double? amount) {
    if (_paid || !mounted) return;
    _poll?.cancel();
    HapticFeedback.heavyImpact();
    setState(() {
      _paid = true;
      if (amount != null) _amount = amount;
    });
  }

  @override
  Widget build(BuildContext context) {
    final amountText = _amount != null ? 'GHS ${_amount!.toStringAsFixed(2)}' : '';
    final color = _paid ? CollectorColors.green : CollectorColors.warning;
    return Scaffold(
      backgroundColor: CollectorColors.dark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Container(
                width: 120,
                height: 120,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color.withAlpha(30)),
                child: _paid
                    ? Icon(Icons.check_circle_rounded, color: color, size: 84)
                    : SizedBox(width: 64, height: 64, child: CircularProgressIndicator(color: color, strokeWidth: 5)),
              ),
              const SizedBox(height: 28),
              Text(
                _paid ? 'Payment received' : 'Waiting for the customer to pay',
                textAlign: TextAlign.center,
                style: CollectorType.hero.copyWith(fontSize: 26),
              ),
              const SizedBox(height: 10),
              if (amountText.isNotEmpty)
                Text(amountText,
                    textAlign: TextAlign.center,
                    style: CollectorType.title.copyWith(color: color, fontSize: 30)),
              const SizedBox(height: 12),
              Text(
                _paid
                    ? 'The customer has paid in the app. You can head off.'
                    : 'Ask the customer to tap "Make payment" in BinLink Eco and approve the mobile money prompt. This screen updates by itself.',
                textAlign: TextAlign.center,
                style: CollectorType.body.copyWith(color: const Color(0xFFC8D0DA)),
              ),
              const Spacer(),
              CButton(
                label: _paid ? 'DONE' : 'LEAVE WITHOUT WAITING',
                icon: 'navigation',
                secondary: !_paid,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              if (!_paid) ...[
                const SizedBox(height: 10),
                Text('You will still get a notification when they pay.',
                    textAlign: TextAlign.center, style: CollectorType.caption),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
