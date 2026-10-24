import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A "slide to confirm" action button. The user must drag the thumb to the far
/// end to trigger [onConfirmed] — prevents accidental taps on destructive /
/// one-way actions (e.g. the collector marking "Arrived" or "Collected").
///
/// While [onConfirmed] runs the thumb shows a spinner; on failure the track
/// snaps back so the action can be retried.
class SlideToConfirm extends StatefulWidget {
  final String label;
  final Future<bool> Function() onConfirmed;
  final Color trackColor;
  final Color fillColor;
  final Color thumbColor;
  final Color textColor;
  final IconData icon;
  final double height;

  const SlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.trackColor = const Color(0xFFE8F0EC),
    this.fillColor = const Color(0xFF1B7A4B),
    this.thumbColor = Colors.white,
    this.textColor = const Color(0xFF0B3B2E),
    this.icon = Icons.chevron_right,
    this.height = 60,
  });

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm> {
  double _dx = 0;
  bool _loading = false;
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final maxW = constraints.maxWidth;
      final thumb = widget.height - 8;
      final travel = (maxW - thumb - 8).clamp(1.0, double.infinity);
      final progress = (_dx / travel).clamp(0.0, 1.0);

      Future<void> settle() async {
        if (_loading) return;
        if (progress >= 0.9) {
          setState(() { _loading = true; _dx = travel; });
          HapticFeedback.mediumImpact();
          bool ok = false;
          try { ok = await widget.onConfirmed(); } catch (_) { ok = false; }
          if (!mounted) return;
          setState(() { _loading = false; _done = ok; if (!ok) _dx = 0; });
        } else {
          setState(() => _dx = 0);
        }
      }

      return Semantics(
        label: widget.label,
        button: true,
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: widget.trackColor,
            borderRadius: BorderRadius.circular(widget.height / 2),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Fill grows behind the thumb as you slide.
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: (_dx + thumb + 8).clamp(thumb + 8, maxW),
                  height: widget.height,
                  decoration: BoxDecoration(
                    color: widget.fillColor.withOpacity(0.15 + 0.85 * progress),
                    borderRadius: BorderRadius.circular(widget.height / 2),
                  ),
                ),
              ),
              Text(
                _done ? 'Done' : widget.label,
                style: TextStyle(
                  color: widget.textColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  letterSpacing: 0.3,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onHorizontalDragUpdate: _loading || _done ? null : (d) {
                    setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, travel));
                  },
                  onHorizontalDragEnd: _loading || _done ? null : (_) => settle(),
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    width: thumb,
                    height: thumb,
                    transform: Matrix4.translationValues(_dx, 0, 0),
                    decoration: BoxDecoration(
                      color: widget.thumbColor,
                      shape: BoxShape.circle,
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                    ),
                    child: _loading
                        ? Padding(
                            padding: const EdgeInsets.all(14),
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: widget.fillColor),
                          )
                        : Icon(_done ? Icons.check : widget.icon, color: widget.fillColor, size: 28),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
