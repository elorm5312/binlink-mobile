import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'app_haptics.dart';

class CollectorAssets {
  static const root = 'assets/collector_assets';

  // Branding
  static const logo            = '$root/branding/collector_logo.svg';
  static const badge           = '$root/branding/collector_badge.png';

  // Onboarding (PNG — GPT Image)
  static const welcome         = '$root/onboarding/collector_welcome.png';
  static const earnMoney       = '$root/onboarding/earn_money.png';
  static const navigateRoutes  = '$root/onboarding/navigate_routes.png';
  static const completePickups = '$root/onboarding/complete_pickups.png';

  // Illustrations (PNG — from GPT Image)
  static const offline         = '$root/illustrations/collector_offline.png';

  // Empty states
  static const noJobs          = '$root/empty_states/no_jobs.svg';
  static const noNotifications = '$root/empty_states/no_notifications.svg';

  // Fleet icons (PNG — from GPT Image)
  static const fleetMiniTruck  = '$root/icons/fleet/fleet_mini_truck.png';
  static const fleetCompactor  = '$root/icons/fleet/fleet_compactor.png';
  static const fleetDumpTruck  = '$root/icons/fleet/fleet_dump_truck.png';
  static const fleetCargoTruck = '$root/icons/fleet/fleet_cargo_truck.png';
  static const fleetSkipTruck  = '$root/icons/fleet/fleet_skip_truck.png';


  // Wallet & earnings
  static const wallet          = '$root/earnings/wallet.svg';
  static const earningsBonus   = '$root/earnings/bonus.svg';
  static const earningsHistory = '$root/earnings/history.svg';
  static const noTransactions  = '$root/empty_states/no_transactions.svg';

  // Map markers (PNG)
  static const truckMarker         = '$root/map_markers/truck_marker.png';
  static const activeTruckMarker   = '$root/map_markers/active_truck_marker.png';
  static const pickupMarker        = '$root/map_markers/pickup_marker.png';
  static const destinationMarker   = '$root/map_markers/destination_marker.png';
  static const collectorMarker     = '$root/map_markers/collector_marker.png';

  // Lottie
  static const incomingRequest = '$root/lottie/incoming_request.json';
  static const loadingLottie   = '$root/lottie/loading.json';
}

/// Collector palette — green-on-black (default) / green-on-white (light).
///
/// Same pattern as HouseholdColors: theme-switched getters keyed off [isDark],
/// flipped by ThemeProvider before the tree rebuilds. Semantic names keep
/// their roles across modes: `dark` = scaffold background, `charcoal` = panel
/// surface, `white` = primary text, `line` = hairlines.
class CollectorColors {
  static bool isDark = true;

  // Brand green (was amber 0xFFD97706 pre-rebrand). Buttons draw `dark` text
  // on it, so it stays bright.
  static Color get green  => isDark ? const Color(0xFF2BD97B) : const Color(0xFF16A34A);
  static Color get forest => isDark ? const Color(0xFFD7F5E4) : const Color(0xFF0B3B2E);

  // Surfaces
  static Color get dark     => isDark ? const Color(0xFF0B100D) : const Color(0xFFF4F7F4);
  static Color get charcoal => isDark ? const Color(0xFF161D18) : Colors.white;
  static Color get line     => isDark ? const Color(0xFF25322A) : const Color(0xFFE3E8E3);

  // Text
  static Color get white => isDark ? const Color(0xFFFAFAF9) : const Color(0xFF16241C);
  static Color get gray  => isDark ? const Color(0xFF9AA8A0) : const Color(0xFF6B7280);
  static Color get muted => isDark ? const Color(0xFF95A1B2) : const Color(0xFF8A948E);

  // Accents / status
  static Color get blue    => const Color(0xFF3B82F6);
  static Color get warning => const Color(0xFFF59E0B);
  static Color get payout  => const Color(0xFFEA580C);
  static Color get red     => isDark ? const Color(0xFFF87171) : const Color(0xFFEF4444);
  static Color get success => const Color(0xFF22C55E);
}

class CollectorType {
  static const _sans = 'PlusJakartaSans';
  static const _mono = 'DMMono';
  static TextStyle get hero => TextStyle(fontFamily: _sans, fontSize: 36, height: 1.0, fontWeight: FontWeight.w800, color: CollectorColors.white);
  static TextStyle get title => TextStyle(fontFamily: _sans, fontSize: 24, height: 1.1, fontWeight: FontWeight.w800, color: CollectorColors.white);
  static TextStyle get section => TextStyle(fontFamily: _sans, fontSize: 17, fontWeight: FontWeight.w800, color: CollectorColors.white);
  static TextStyle get body => TextStyle(fontFamily: _sans, fontSize: 15, height: 1.42, fontWeight: FontWeight.w500, color: CollectorColors.white);
  static TextStyle get caption => TextStyle(fontFamily: _sans, fontSize: 12, fontWeight: FontWeight.w500, color: CollectorColors.isDark ? const Color(0xFFB6C0CC) : const Color(0xFF6B7280));
  static TextStyle get number => TextStyle(fontFamily: _mono, fontSize: 16, fontWeight: FontWeight.w600, color: CollectorColors.white);
}

class CIcon extends StatelessWidget {
  const CIcon(this.name, {super.key, this.size = 24, this.color});
  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Icon(_collectorIcon(name), size: size, color: color);
  }
}

IconData _collectorIcon(String name) {
  switch (name) {
    case 'truck': return PhosphorIcons.truck();
    case 'map': return PhosphorIcons.mapTrifold();
    case 'route': return PhosphorIcons.caretLeft();
    case 'jobs': return PhosphorIcons.clipboardText();
    case 'wallet': return PhosphorIcons.wallet();
    case 'earnings': return PhosphorIcons.coins();
    case 'fuel': return PhosphorIcons.gasPump();
    case 'capacity': return PhosphorIcons.gauge();
    case 'warehouse': return PhosphorIcons.warehouse();
    case 'landfill': return PhosphorIcons.trash();
    case 'recycle': return PhosphorIcons.recycle();
    case 'performance': return PhosphorIcons.chartLineUp();
    case 'rating': return PhosphorIcons.star();
    case 'reviews': return PhosphorIcons.chatCircleText();
    case 'maintenance': return PhosphorIcons.wrench();
    case 'calendar': return PhosphorIcons.calendar();
    case 'notifications': return PhosphorIcons.bell();
    case 'profile': return PhosphorIcons.user();
    case 'settings': return PhosphorIcons.gear();
    case 'chat': return PhosphorIcons.chatCircle();
    case 'phone': return PhosphorIcons.phone();
    case 'camera': return PhosphorIcons.camera();
    case 'before_photo': return PhosphorIcons.camera();
    case 'after_photo': return PhosphorIcons.image();
    case 'weight': return PhosphorIcons.scales();
    case 'scan': return PhosphorIcons.scan();
    case 'package': return PhosphorIcons.package();
    case 'navigation': return PhosphorIcons.navigationArrow();
    case 'location': return PhosphorIcons.mapPin();
    case 'clock': return PhosphorIcons.clock();
    case 'bonus': return PhosphorIcons.gift();
    case 'withdrawal': return PhosphorIcons.arrowUpRight();
    case 'history': return PhosphorIcons.clockCounterClockwise();
    case 'star': return PhosphorIcons.star();
    case 'help': return PhosphorIcons.question();
    case 'support': return PhosphorIcons.lifebuoy();
    case 'privacy': return PhosphorIcons.shield();
    case 'security': return PhosphorIcons.lockKey();
    case 'emergency': return PhosphorIcons.warning();
    case 'dark_mode': return PhosphorIcons.moon();
    case 'language': return PhosphorIcons.globe();
    case 'offline': return PhosphorIcons.wifiSlash();
    case 'online': return PhosphorIcons.wifiHigh();
    default: return PhosphorIcons.circle();
  }
}

class CButton extends StatelessWidget {
  const CButton({super.key, required this.label, required this.onPressed, this.icon, this.danger = false, this.secondary = false, this.loading = false});
  final String label;
  final VoidCallback? onPressed;
  final String? icon;
  final bool danger;
  final bool secondary;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final bg = danger ? CollectorColors.red : secondary ? CollectorColors.charcoal : CollectorColors.green;
    final fg = secondary ? CollectorColors.white : CollectorColors.dark;
    final enabled = !loading && onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: SizedBox(
      height: 60,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(24), border: Border.all(color: secondary ? CollectorColors.line : bg)),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
              onTap: enabled
                  ? () {
                      AppHaptics.light();
                      onPressed!();
                    }
                  : null,
              child: Center(
                child: loading
                  ? _LoadingDots(color: fg)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[CIcon(icon!, size: 20, color: fg), const SizedBox(width: 10)],
                        Text(label, style: CollectorType.body.copyWith(color: fg, fontWeight: FontWeight.w900, letterSpacing: .2)),
                      ],
                    ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _LoadingDots extends StatefulWidget {
  const _LoadingDots({required this.color});
  final Color color;

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final t = _controller.value;
        return SizedBox(
          width: 30,
          height: 14,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(3, (i) {
              final phase = (t + i * 0.18) % 1;
              final scale = 0.65 + (phase < .5 ? phase : 1 - phase) * 0.7;
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class CPanel extends StatelessWidget {
  const CPanel({super.key, required this.child, this.padding = const EdgeInsets.all(20)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: CollectorColors.charcoal,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: CollectorColors.line),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 24, offset: Offset(0, 14))],
      ),
      child: child,
    );
  }
}

class CTextField extends StatelessWidget {
  const CTextField({super.key, required this.controller, required this.label, this.hint, this.validator, this.obscure = false, this.keyboardType, this.inputFormatters});
  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? Function(String?)? validator;
  final bool obscure;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      obscureText: obscure,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: CollectorType.body,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: CollectorColors.charcoal,
        labelStyle: CollectorType.caption,
        hintStyle: CollectorType.caption,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: CollectorColors.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: CollectorColors.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: CollectorColors.green, width: 1.4)),
      ),
    );
  }
}

class CBottomNav extends StatelessWidget {
  const CBottomNav({super.key, required this.index, required this.onChanged, required this.items});
  final int index;
  final ValueChanged<int> onChanged;
  final List<({String label, String icon})> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: 72,
            decoration: BoxDecoration(color: CollectorColors.dark.withAlpha(232), borderRadius: BorderRadius.circular(30), border: Border.all(color: CollectorColors.line)),
            child: Row(
              children: List.generate(items.length, (i) {
                final active = i == index;
                return Expanded(
                  child: Semantics(
                    button: true,
                    selected: active,
                    label: items[i].label,
                    child: InkWell(
                    onTap: () {
                      AppHaptics.selection();
                      onChanged(i);
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CIcon(items[i].icon, size: 24, color: active ? CollectorColors.green : CollectorColors.muted),
                        const SizedBox(height: 5),
                        Text(items[i].label, style: CollectorType.caption.copyWith(color: active ? CollectorColors.green : CollectorColors.muted, fontWeight: active ? FontWeight.w800 : FontWeight.w500)),
                      ],
                    ),
                  ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
