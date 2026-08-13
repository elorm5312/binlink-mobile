import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../../core/design_system/collector_design_system.dart';
import '../providers/collector_provider.dart';
import '../screens/active_pickup_screen.dart';

/// Full-screen takeover shown to an ONLINE collector the moment a job arrives —
/// rendered at the shell level so it covers every tab AND the bottom nav. Plays
/// a loud looping ringtone + haptics until the collector accepts, declines, or
/// the 30-second auto-reject fires.
class IncomingRequestOverlay extends StatefulWidget {
  const IncomingRequestOverlay({super.key, required this.request});
  final Map<String, dynamic> request;

  @override
  State<IncomingRequestOverlay> createState() => _IncomingRequestOverlayState();
}

class _IncomingRequestOverlayState extends State<IncomingRequestOverlay>
    with SingleTickerProviderStateMixin {
  static const _seconds = 30;
  late final AnimationController _ring =
      AnimationController(vsync: this, duration: const Duration(seconds: _seconds))..forward();
  late Timer _timer;
  Timer? _hapticTimer;
  final AudioPlayer _player = AudioPlayer();
  int _remaining = _seconds;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _startAlert();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _handled) return;
      if (_remaining <= 1) {
        _handled = true;
        _timer.cancel();
        _stopAlert();
        context.read<CollectorProvider>().declineRequest(widget.request['id'] as String);
        return;
      }
      setState(() => _remaining -= 1);
    });
  }

  Future<void> _startAlert() async {
    HapticFeedback.heavyImpact();
    // Repeat the haptic while ringing so it's felt even in a pocket.
    _hapticTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (mounted && !_handled) HapticFeedback.mediumImpact();
    });
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      await _player.play(AssetSource('sounds/ringtone.wav'), volume: 1.0);
    } catch (_) {
      // Fall back to the system alert tone if the asset player is unavailable.
      SystemSound.play(SystemSoundType.alert);
    }
  }

  Future<void> _stopAlert() async {
    _hapticTimer?.cancel();
    try {
      await _player.stop();
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant IncomingRequestOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request['id'] != widget.request['id']) {
      _remaining = _seconds;
      _handled = false;
      _ring.forward(from: 0);
      _startAlert();
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    _hapticTimer?.cancel();
    _ring.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<CollectorProvider>();
    return Material(
      type: MaterialType.transparency,
      child: Container(
        color: Colors.black.withAlpha(230),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(children: [
              const Spacer(),
              SizedBox(
                height: 210,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _ring,
                      builder: (_, __) => CustomPaint(
                        size: const Size(210, 210),
                        painter: _CountdownRingPainter(progress: _ring.value, color: CollectorColors.warning),
                      ),
                    ),
                    SvgPicture.asset('assets/collector_assets/workflow/accept_request.svg', height: 150),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text('Incoming request', style: CollectorType.hero, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(widget.request['pickupAddress'] as String? ?? 'Pickup location nearby',
                  textAlign: TextAlign.center,
                  style: CollectorType.body.copyWith(color: const Color(0xFFC8D0DA))),
              const SizedBox(height: 6),
              Text('Auto reject in $_remaining s',
                  style: CollectorType.caption.copyWith(color: CollectorColors.warning)),
              const Spacer(),
              CButton(label: 'TAP TO ACCEPT', icon: 'jobs', onPressed: () async {
                _handled = true;
                _timer.cancel();
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                await _stopAlert();
                final booking = await provider.acceptRequest(widget.request['id'] as String);
                if (booking == null) {
                  messenger.showSnackBar(SnackBar(
                      content: Text(provider.error ?? 'Could not accept — it may have been taken.')));
                  return;
                }
                navigator.push(MaterialPageRoute(builder: (_) => ActivePickupScreen(booking: booking)));
              }),
              const SizedBox(height: 12),
              CButton(label: 'DECLINE', danger: true, secondary: true, onPressed: () async {
                _handled = true;
                _timer.cancel();
                await _stopAlert();
                await provider.declineRequest(widget.request['id'] as String);
              }),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CountdownRingPainter extends CustomPainter {
  const _CountdownRingPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 10;
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = Colors.white.withAlpha(30);
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawCircle(center, radius, bg);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -1.57, 6.28318 * progress, false, fg);
  }

  @override
  bool shouldRepaint(covariant _CountdownRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
