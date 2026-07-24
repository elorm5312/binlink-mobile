import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'app_haptics.dart';

class HouseholdAssets {
  static const root = 'assets/household_assets';

  // Branding
  static const logo            = '$root/branding/binlink_logo.png';
  static const appIcon         = '$root/branding/app_icon.png';

  // Onboarding (SVG — flat design, BinLink palette)
  static const cleanCity       = '$root/onboarding/clean_city.svg';
  static const bookPickup      = '$root/onboarding/book_pickup.svg';
  static const trackCollectors = '$root/onboarding/track_collectors.svg';
  static const earnRewards     = '$root/onboarding/earn_rewards.svg';

  // Illustrations (PNG — GPT Image)
  static const pickupComplete  = '$root/illustrations/pickup_complete.png';
  static const loginHero       = '$root/illustrations/login_hero.png';
  static const registerHero    = '$root/illustrations/register_hero.png';
  static const otpVerify       = '$root/illustrations/otp_verification.png';

  // SVG illustrations (replace with PNG when GPT assets arrive)
  static const liveMap         = '$root/illustrations/live_map.svg';
  static const schedulePickup  = '$root/illustrations/schedule_pickup.svg';
  static const forgotPassword  = '$root/empty_states/no_data.svg';
  static const searching       = '$root/tracking/searching_collector.svg';
  static const arriving        = '$root/tracking/collector_arriving.svg';
  static const complete        = '$root/illustrations/pickup_complete.png';
  static const networkError    = '$root/errors/network_error.svg';

  // Wallet & rewards (PNG — from GPT Image)
  static const ecoPoints       = '$root/wallet/eco_points.png';
  static const carbonSavings   = '$root/history/carbon_savings.png';
  static const wallet          = '$root/wallet/wallet.svg';
  static const rewards         = '$root/wallet/rewards.svg';

  // Empty states
  static const noPickups       = '$root/empty_states/no_pickups.png';
  static const noWallet        = '$root/empty_states/no_wallet.svg';
  static const noHistory       = '$root/empty_states/no_history.svg';
  static const noNotifications = '$root/empty_states/no_notifications.svg';
  static const noData          = '$root/empty_states/no_data.svg';

  // Waste category chips (SVG — flat design icons, BinLink palette)
  static const householdBin    = '$root/waste_categories/household_bin.svg';
  static const plasticBin      = '$root/waste_categories/plastic_bin.svg';
  static const organicBin      = '$root/waste_categories/organic_bin.svg';
  static const ewasteBin       = '$root/waste_categories/ewaste_bin.svg';
  static const glassBin        = '$root/waste_categories/glass_bin.svg';
  static const metalBin        = '$root/waste_categories/metal_bin.svg';
  static const constructionBin = '$root/waste_categories/construction_bin.svg';
  static const medicalBin      = '$root/waste_categories/medical_bin.svg';
  static const bulkyBin        = '$root/waste_categories/bulky_bin.svg';

  // Map markers (PNG)
  static const truckMarker       = '$root/map_markers/truck_marker.png';
  static const pickupMarker      = '$root/map_markers/pickup_marker.png';
  static const destinationMarker = '$root/map_markers/destination_marker.png';
  static const userMarker        = '$root/map_markers/user_marker.png';
  static const collectorMarker   = '$root/map_markers/collector_marker.png';

  // Lottie
  static const loadingLottie = '$root/lottie/loading.json';
  static const successLottie = '$root/lottie/success.json';
}

/// BinLink brand palette — "green on white" (light) / "green on black" (dark).
///
/// Colors are theme-switched getters, not consts: [isDark] is flipped by
/// ThemeProvider before the tree rebuilds. Semantic names keep their roles in
/// both modes (charcoal = primary text, sand = scaffold background, card =
/// raised surface, border = hairlines), so call sites don't need to branch.
class HouseholdColors {
  static bool isDark = false;

  // Brand greens. Dark primary stays deep enough to carry the white text that
  // existing call sites draw on primary-filled surfaces.
  static Color get primary  => isDark ? const Color(0xFF1FBF63) : const Color(0xFF16A34A);
  static Color get ecoGreen => isDark ? const Color(0xFF2BD97B) : const Color(0xFF19B661);
  static Color get forest   => isDark ? const Color(0xFFD7F5E4) : const Color(0xFF0B3B2E);

  // Text
  static Color get charcoal => isDark ? const Color(0xFFE8EDEA) : const Color(0xFF1F2937);
  static Color get gray     => isDark ? const Color(0xFF9AA8A0) : const Color(0xFF6B7280);

  // Surfaces
  static Color get warmWhite => isDark ? const Color(0xFF101613) : const Color(0xFFFAFAF9);
  static Color get sand      => isDark ? const Color(0xFF0A0F0C) : const Color(0xFFF4F7F4);
  static Color get card      => isDark ? const Color(0xFF151C17) : Colors.white;
  static Color get border    => isDark ? const Color(0xFF25322A) : const Color(0xFFE3E8E3);

  // Accents / status
  static Color get blue    => const Color(0xFF3B82F6);
  static Color get warning => const Color(0xFFF59E0B);
  static Color get danger  => isDark ? const Color(0xFFF87171) : const Color(0xFFEF4444);

  /// Text/icon color on top of [primary]-filled surfaces.
  static Color get onPrimary => Colors.white;

  // Soft tint cards (info banners, inline errors) — dark variants keep text readable.
  static Color get infoTint   => isDark ? const Color(0xFF12212E) : const Color(0xFFF0F7FF);
  static Color get dangerTint => isDark ? const Color(0xFF2A1518) : const Color(0xFFFFF1F2);

  /// Soft shadow tint for cards.
  static Color get shadow => isDark ? Colors.black.withAlpha(90) : const Color(0xFF0B3B2E).withAlpha(20);
}

class HouseholdType {
  static const _sans = 'PlusJakartaSans';
  static const _mono = 'DMMono';
  static TextStyle get hero => TextStyle(fontFamily: _sans, fontSize: 34, height: 1.04, fontWeight: FontWeight.w700, color: HouseholdColors.forest);
  static TextStyle get title => TextStyle(fontFamily: _sans, fontSize: 24, height: 1.12, fontWeight: FontWeight.w700, color: HouseholdColors.charcoal);
  static TextStyle get section => TextStyle(fontFamily: _sans, fontSize: 17, fontWeight: FontWeight.w700, color: HouseholdColors.charcoal);
  static TextStyle get body => TextStyle(fontFamily: _sans, fontSize: 15, height: 1.45, fontWeight: FontWeight.w500, color: HouseholdColors.charcoal);
  static TextStyle get caption => TextStyle(fontFamily: _sans, fontSize: 12, height: 1.35, fontWeight: FontWeight.w400, color: HouseholdColors.gray);
  static TextStyle get number => TextStyle(fontFamily: _mono, fontSize: 16, fontWeight: FontWeight.w600, color: HouseholdColors.charcoal);
}

class HIcon extends StatelessWidget {
  const HIcon(this.name, {super.key, this.size = 24, this.color});
  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Icon(_householdIcon(name), size: size, color: color);
  }
}

IconData _householdIcon(String name) {
  switch (name) {
    case 'home': return PhosphorIcons.house();
    case 'pickup': return PhosphorIcons.truck();
    case 'pickups': return PhosphorIcons.truck();
    case 'history': return PhosphorIcons.clockCounterClockwise();
    case 'wallet': return PhosphorIcons.wallet();
    case 'rewards': return PhosphorIcons.gift();
    case 'tracking': return PhosphorIcons.navigationArrow();
    case 'notifications': return PhosphorIcons.bell();
    case 'profile': return PhosphorIcons.user();
    case 'settings': return PhosphorIcons.gear();
    case 'support': return PhosphorIcons.lifebuoy();
    case 'map': return PhosphorIcons.mapTrifold();
    case 'location': return PhosphorIcons.mapPin();
    case 'calendar': return PhosphorIcons.calendar();
    case 'schedule': return PhosphorIcons.clock();
    case 'chat': return PhosphorIcons.chatCircle();
    case 'phone': return PhosphorIcons.phone();
    case 'payment': return PhosphorIcons.creditCard();
    case 'coupon': return PhosphorIcons.ticket();
    case 'star': return PhosphorIcons.star();
    case 'rating': return PhosphorIcons.star();
    case 'privacy': return PhosphorIcons.shield();
    case 'security': return PhosphorIcons.lockKey();
    case 'dark_mode': return PhosphorIcons.moon();
    case 'language': return PhosphorIcons.globe();
    case 'search': return PhosphorIcons.magnifyingGlass();
    case 'truck': return PhosphorIcons.truck();
    case 'recycle': return PhosphorIcons.recycle();
    case 'route': return PhosphorIcons.caretLeft();
    case 'clock': return PhosphorIcons.clock();
    case 'carbon': return PhosphorIcons.leaf();
    case 'eco_points': return PhosphorIcons.leaf();
    default: return PhosphorIcons.circle();
  }
}

class HButton extends StatelessWidget {
  const HButton({super.key, required this.label, required this.onPressed, this.icon, this.secondary = false, this.loading = false});
  final String label;
  final VoidCallback? onPressed;
  final String? icon;
  final bool secondary;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final fg = secondary ? HouseholdColors.forest : Colors.white;
    final enabled = !loading && onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: onPressed == null ? .45 : 1,
      child: SizedBox(
        height: 56,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: secondary ? HouseholdColors.card : HouseholdColors.primary,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: secondary ? HouseholdColors.border : HouseholdColors.primary),
            boxShadow: secondary ? null : [BoxShadow(color: HouseholdColors.primary.withAlpha(54), blurRadius: 22, offset: const Offset(0, 10))],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
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
                          if (icon != null) ...[HIcon(icon!, size: 20, color: fg), const SizedBox(width: 10)],
                          Text(label, style: HouseholdType.body.copyWith(color: fg, fontWeight: FontWeight.w700)),
                        ],
                      ),
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

class HCard extends StatelessWidget {
  const HCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.radius = 28, this.color});
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? HouseholdColors.card,
        borderRadius: BorderRadius.circular(radius),
        border: HouseholdColors.isDark ? Border.all(color: HouseholdColors.border) : null,
        boxShadow: [BoxShadow(color: HouseholdColors.shadow, blurRadius: 28, offset: const Offset(0, 14))],
      ),
      child: child,
    );
  }
}

class HTextField extends StatelessWidget {
  const HTextField({super.key, required this.controller, required this.label, this.hint, this.validator, this.obscure = false, this.keyboardType, this.inputFormatters});
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
      style: HouseholdType.body,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: HouseholdColors.card,
        labelStyle: HouseholdType.caption,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: HouseholdColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: HouseholdColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: HouseholdColors.primary, width: 1.4)),
      ),
    );
  }
}

class HBottomNav extends StatelessWidget {
  const HBottomNav({super.key, required this.index, required this.onChanged, required this.items});
  final int index;
  final ValueChanged<int> onChanged;
  final List<({String label, String icon})> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: 72,
            decoration: BoxDecoration(color: HouseholdColors.card.withAlpha(232), borderRadius: BorderRadius.circular(36), border: Border.all(color: HouseholdColors.isDark ? HouseholdColors.border : Colors.white)),
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
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
                      decoration: BoxDecoration(color: active ? HouseholdColors.primary.withAlpha(24) : Colors.transparent, borderRadius: BorderRadius.circular(28)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          HIcon(items[i].icon, size: 23, color: active ? HouseholdColors.primary : HouseholdColors.gray),
                          const SizedBox(height: 4),
                          Text(items[i].label, style: HouseholdType.caption.copyWith(color: active ? HouseholdColors.forest : HouseholdColors.gray, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
                        ],
                      ),
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

class HScaffold extends StatelessWidget {
  const HScaffold({super.key, required this.child, this.background});
  final Widget child;
  final Color? background;

  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: background ?? HouseholdColors.sand, body: SafeArea(child: child));
}
