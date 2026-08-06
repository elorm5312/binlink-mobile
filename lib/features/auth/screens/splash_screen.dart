import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/app_flavor.dart';
import '../../../core/design_system/collector_design_system.dart';
import '../../../core/design_system/household_design_system.dart';
import '../providers/auth_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Future.wait([
      context.read<AuthProvider>().initialize(),
      Future.delayed(const Duration(milliseconds: 1100)),
    ]);
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (auth.status == AuthStatus.authenticated) {
      final route = auth.user?.isAdmin == true
          ? '/admin'
          : (FlavorConfig.isCollector ? '/collector' : '/household');
      Navigator.pushReplacementNamed(context, route);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, (prefs.getBool('show_onboarding') ?? true) ? '/onboarding' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    if (FlavorConfig.isCollector) {
      return Scaffold(
        backgroundColor: CollectorColors.dark,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(CollectorAssets.badge, width: 120),
              const SizedBox(height: 30),
              Lottie.asset('assets/collector_assets/lottie/loading.json', width: 92, height: 92),
              const SizedBox(height: 16),
              Text('Field operations online', style: CollectorType.caption),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: HouseholdColors.sand,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(HouseholdAssets.logo, width: 230),
            const SizedBox(height: 28),
            Lottie.asset(HouseholdAssets.loadingLottie, width: 92, height: 92),
            const SizedBox(height: 12),
            Text('Cleaner pickups for Ghana', style: HouseholdType.caption.copyWith(color: HouseholdColors.forest)),
          ],
        ),
      ),
    );
  }
}
