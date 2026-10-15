import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/call_service.dart';
import '../../core/services/phone_launcher.dart';
import '../../core/config/app_flavor.dart';

/// Full-screen in-app voice call UI (ringing, connecting, in-call, ended).
/// All state lives in [CallService]; this screen only renders it.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _call = CallService.instance;
  Timer? _tick;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _call.addListener(_onChange);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _call.phase == CallPhase.active) setState(() {});
    });
  }

  @override
  void dispose() {
    _call.removeListener(_onChange);
    _tick?.cancel();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    if (_call.phase == CallPhase.ended && !_closing && !_offerPhoneFallback) {
      _closing = true;
      Future.delayed(const Duration(milliseconds: 1500), _close);
    }
  }

  void _close() {
    _call.dismiss();
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  /// After a failed or unanswered call, offer a normal phone call instead.
  bool get _offerPhoneFallback =>
      _call.phase == CallPhase.ended &&
      _call.isCaller &&
      (_call.peerPhone ?? '').isNotEmpty &&
      const {'failed', 'no_answer', 'disconnected'}.contains(_call.endReason);

  String get _status {
    switch (_call.phase) {
      case CallPhase.outgoing:
        return 'Ringing…';
      case CallPhase.incoming:
        return 'Incoming ${FlavorConfig.appName} call';
      case CallPhase.connecting:
        return 'Connecting…';
      case CallPhase.active:
        final s = DateTime.now().difference(_call.connectedAt ?? DateTime.now()).inSeconds;
        return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
      case CallPhase.ended:
        return switch (_call.endReason) {
          'declined' => 'Call declined',
          'no_answer' => 'No answer',
          'failed' => 'Could not connect the call',
          'mic_denied' => 'Microphone access is needed for calls',
          'disconnected' => 'Call dropped',
          'answered_elsewhere' => 'Answered on another device',
          _ => 'Call ended',
        };
      case CallPhase.idle:
        return '';
    }
  }

  String get _initials {
    final parts = _call.peerName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF2BD97B);
    final phase = _call.phase;

    return PopScope(
      canPop: phase == CallPhase.ended || phase == CallPhase.idle,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0B3B2E), Color(0xFF07130E)],
            ),
          ),
          child: SafeArea(
            child: Column(children: [
              const SizedBox(height: 56),
              _Pulse(active: phase == CallPhase.outgoing || phase == CallPhase.incoming, child: CircleAvatar(
                radius: 52,
                backgroundColor: accent.withAlpha(40),
                child: Text(_initials,
                    style: const TextStyle(color: accent, fontSize: 34, fontWeight: FontWeight.w800)),
              )),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(_call.peerName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontFamily: 'PlusJakartaSans', color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 8),
              Text(_status, style: const TextStyle(color: Color(0xFFB6C7BD), fontSize: 15)),
              const SizedBox(height: 6),
              Text('Free call over the internet · ${FlavorConfig.appName}',
                  style: const TextStyle(color: Color(0xFF6E8579), fontSize: 12)),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
                child: _controls(phase),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _controls(CallPhase phase) {
    if (phase == CallPhase.incoming) {
      return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _RoundButton(icon: Icons.call_end, color: const Color(0xFFEF4444), label: 'Decline', onTap: _call.decline),
        _RoundButton(icon: Icons.call, color: const Color(0xFF22C55E), label: 'Answer', onTap: _call.accept),
      ]);
    }
    if (phase == CallPhase.ended) {
      if (!_offerPhoneFallback) return const SizedBox(height: 96);
      return Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2BD97B),
              foregroundColor: const Color(0xFF07130E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
            ),
            icon: const Icon(Icons.phone_forwarded),
            label: const Text('Call their phone instead', style: TextStyle(fontWeight: FontWeight.w700)),
            onPressed: () {
              final phone = _call.peerPhone;
              _close();
              PhoneLauncher.call(phone);
            },
          ),
        ),
        TextButton(onPressed: _close, child: const Text('Close', style: TextStyle(color: Color(0xFFB6C7BD)))),
      ]);
    }
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _RoundButton(
        icon: _call.muted ? Icons.mic_off : Icons.mic,
        color: _call.muted ? Colors.white : const Color(0x33FFFFFF),
        iconColor: _call.muted ? const Color(0xFF07130E) : Colors.white,
        label: _call.muted ? 'Unmute' : 'Mute',
        onTap: _call.toggleMute,
      ),
      _RoundButton(icon: Icons.call_end, color: const Color(0xFFEF4444), label: 'End', onTap: () => _call.hangUp()),
      _RoundButton(
        icon: Icons.volume_up,
        color: _call.speaker ? Colors.white : const Color(0x33FFFFFF),
        iconColor: _call.speaker ? const Color(0xFF07130E) : Colors.white,
        label: 'Speaker',
        onTap: _call.toggleSpeaker,
      ),
    ]);
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.iconColor = Colors.white,
  });

  final IconData icon;
  final Color color;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 68, height: 68, child: Icon(icon, color: iconColor, size: 30)),
        ),
      ),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(color: Color(0xFFB6C7BD), fontSize: 12)),
    ]);
  }
}

/// Soft expanding rings behind the avatar while the call is ringing.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: 184, height: 184, child: Center(child: widget.active ? _rings() : widget.child));
  }

  Widget _rings() {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Stack(alignment: Alignment.center, children: [
        for (final offset in const [0.0, 0.5])
          Builder(builder: (_) {
            final t = (_ctrl.value + offset) % 1.0;
            return Container(
              width: 104 + 80 * t,
              height: 104 + 80 * t,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2BD97B).withAlpha((60 * (1 - t)).round()),
              ),
            );
          }),
        child!,
      ]),
      child: widget.child,
    );
  }
}

/// Call button entry point: lets the user pick a free in-app call or a normal
/// phone call. Shows a snackbar if the in-app call cannot start.
Future<void> showCallOptions(
  BuildContext context, {
  required String? bookingId,
  required String peerName,
  required String? peerPhone,
}) async {
  final hasPhone = (peerPhone ?? '').trim().isNotEmpty;
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text('Call $peerName',
              style: const TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 18, fontWeight: FontWeight.w800)),
        ),
        ListTile(
          enabled: bookingId != null,
          leading: const CircleAvatar(
              backgroundColor: Color(0x222BD97B), child: Icon(Icons.wifi_calling_3, color: Color(0xFF16A34A))),
          title: Text('Free ${FlavorConfig.appName} call', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Uses internet data — no airtime'),
          onTap: () => Navigator.pop(sheet, 'app'),
        ),
        ListTile(
          enabled: hasPhone,
          leading: const CircleAvatar(
              backgroundColor: Color(0x223B82F6), child: Icon(Icons.phone, color: Color(0xFF3B82F6))),
          title: const Text('Phone call', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(hasPhone ? 'Normal call with airtime' : 'No phone number available'),
          onTap: () => Navigator.pop(sheet, 'phone'),
        ),
        const SizedBox(height: 12),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  if (choice == 'phone') {
    final ok = await PhoneLauncher.call(peerPhone);
    if (!ok) messenger.showSnackBar(const SnackBar(content: Text('Could not open the phone dialer.')));
    return;
  }
  final error = await CallService.instance.start(bookingId: bookingId!, peerName: peerName, peerPhone: peerPhone);
  if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
}
