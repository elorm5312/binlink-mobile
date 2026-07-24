import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/config/app_flavor.dart';
import 'core/design_system/theme_provider.dart';
import 'core/l10n/strings.dart';
import 'core/navigation/nav_service.dart';
import 'core/design_system/household_design_system.dart';
import 'core/design_system/collector_design_system.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/splash_screen.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/auth/screens/forgot_password_screen.dart';
import 'features/auth/screens/onboarding_screen.dart';
import 'features/household/providers/household_provider.dart';
import 'features/household/screens/home_screen.dart';
import 'features/household/screens/notifications_screen.dart';
import 'features/household/screens/wallet_screen.dart';
import 'features/household/screens/payment_screen.dart';
import 'features/collector/providers/collector_provider.dart';
import 'features/collector/screens/map_screen.dart';
import 'features/collector/screens/pickups_screen.dart';
import 'features/collector/screens/earnings_screen.dart';
import 'features/collector/screens/collector_notifications_screen.dart';
import 'features/collector/screens/active_pickup_screen.dart';

class BinLinkApp extends StatelessWidget {
  const BinLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) {
          final tp = ThemeProvider();
          tp.load();
          return tp;
        }),
        ChangeNotifierProvider(create: (_) {
          final sp = AppStringsProvider();
          sp.load();
          return sp;
        }),
        ChangeNotifierProvider(create: (_) => HouseholdProvider()),
        ChangeNotifierProvider(create: (_) => CollectorProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (_, themeProv, __) {
          return MaterialApp(
            navigatorKey: NavService.navigatorKey,
            title: FlavorConfig.appName,
            debugShowCheckedModeBanner: false,
            theme: FlavorConfig.isCollector ? _collectorTheme() : _householdTheme(),
            darkTheme: FlavorConfig.isCollector ? _collectorTheme() : _householdTheme(),
            themeMode: themeProv.themeMode,
            // Responsive safety: honor the system font size but clamp it so
            // very large accessibility scales can't break fixed layouts.
            builder: (context, child) => MediaQuery.withClampedTextScaling(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.3,
              child: child ?? const SizedBox.shrink(),
            ),
            initialRoute: '/splash',
            routes: {
              '/splash':          (_) => const SplashScreen(),
              '/onboarding':      (_) => const OnboardingScreen(),
              '/login':           (_) => const LoginScreen(),
              '/register':        (_) => const RegisterScreen(),
              '/forgot-password': (_) => const ForgotPasswordScreen(),
              '/otp':              (_) => const OtpScreen(),
              '/household':       (_) => const HouseholdHomeScreen(),
              '/collector':       (_) => const CollectorMapScreen(),
              '/notifications':   (_) => const NotificationsScreen(),
              '/help':            (_) => const HelpScreen(),
              '/privacy':         (_) => const PrivacyScreen(),
              '/terms':           (_) => const TermsScreen(),
              '/settings':        (_) => const SettingsScreen(),
              '/edit-profile':    (_) => const EditProfileScreen(),
              '/saved-addresses': (_) => const SavedAddressesScreen(),
              '/subscriptions':   (_) => const SubscriptionsScreen(),
              '/wallet':          (_) => const WalletScreen(),
              '/payment':         (_) => const PaymentScreen(),
              '/collector-jobs':   (_) => const PickupsScreen(),
              '/collector-wallet': (_) => const EarningsScreen(),
              '/collector-notifications': (_) => const CollectorNotificationsScreen(),
              '/collector-support': (_) => const CollectorHelpScreen(),
              '/collector-privacy': (_) => const CollectorPrivacyScreen(),
              '/collector-profile-edit': (_) => const CollectorEditProfileScreen(),
              '/collector-vehicle': (_) => const VehicleDetailsScreen(),
              '/collector-reviews': (_) => const CollectorReviewsScreen(),
              '/collector-ratings': (_) => const CollectorRatingsScreen(),
              '/collector-settings': (_) => const CollectorSettingsScreen(),
              '/collector-active-route': (_) => const ActivePickupScreen(),
            },
          );
        },
      ),
    );
  }
}

// Reads the current HouseholdColors palette (ThemeProvider flips isDark before
// notifying, so this always builds against the right palette).
ThemeData _householdTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: HouseholdColors.isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: HouseholdColors.sand,
    colorScheme: ColorScheme.fromSeed(
      seedColor: HouseholdColors.primary,
      brightness: HouseholdColors.isDark ? Brightness.dark : Brightness.light,
      surface: HouseholdColors.card,
    ),
    textTheme: (HouseholdColors.isDark ? ThemeData.dark() : ThemeData.light())
        .textTheme
        .apply(fontFamily: 'PlusJakartaSans', bodyColor: HouseholdColors.charcoal, displayColor: HouseholdColors.forest),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}

// Reads the current CollectorColors palette (ThemeProvider flips isDark before
// notifying, so this always builds against the right palette).
ThemeData _collectorTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: CollectorColors.isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: CollectorColors.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: CollectorColors.green,
      brightness: CollectorColors.isDark ? Brightness.dark : Brightness.light,
      surface: CollectorColors.charcoal,
    ),
    textTheme: (CollectorColors.isDark ? ThemeData.dark() : ThemeData.light())
        .textTheme
        .apply(fontFamily: 'PlusJakartaSans', bodyColor: CollectorColors.white, displayColor: CollectorColors.white),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}
