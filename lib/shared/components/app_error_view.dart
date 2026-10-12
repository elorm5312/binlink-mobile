import 'package:flutter/material.dart';

import '../../core/config/app_flavor.dart';

/// Replaces Flutter's release-mode ErrorWidget (a blank grey box) so a build
/// error never leaves the user stuck on an empty screen. Shows a short error
/// summary for support screenshots and a way back to the home screen.
class AppErrorView extends StatelessWidget {
  const AppErrorView(this.details, {super.key});
  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    final summary = details.exceptionAsString();
    final short = summary.length > 280 ? '${summary.substring(0, 280)}…' : summary;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: const Color(0xFFF4F7F4),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.error_outline_rounded, size: 48, color: Color(0xFF16A34A)),
                const SizedBox(height: 16),
                const Text(
                  'Something went wrong on this screen',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF0B3B2E)),
                ),
                const SizedBox(height: 8),
                Text(
                  short,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 20),
                Builder(
                  builder: (ctx) => FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                    onPressed: () {
                      final nav = Navigator.maybeOf(ctx, rootNavigator: true);
                      nav?.pushNamedAndRemoveUntil(
                        FlavorConfig.isCollector ? '/collector' : '/household',
                        (_) => false,
                      );
                    },
                    child: const Text('Back to home'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
