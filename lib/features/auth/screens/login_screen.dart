import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_flavor.dart';
import '../../../core/design_system/collector_design_system.dart';
import '../../../core/design_system/household_design_system.dart';
import '../../../core/utils/validators.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  // Admins land on the control dashboard; everyone else on their flavor home.
  String _homeRouteFor(AuthProvider auth) {
    if (auth.user?.isAdmin == true) return '/admin';
    return FlavorConfig.isCollector ? '/collector' : '/household';
  }

  Future<void> _loginEmail() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = await auth.loginWithEmail(email: _email.text.trim(), password: _password.text, role: FlavorConfig.defaultRole);
    if (!mounted) return;
    if (ok) {
      Navigator.pushReplacementNamed(context, _homeRouteFor(auth));
    } else {
      _snack(auth.error ?? 'Sign in failed');
    }
  }

  Future<void> _loginGoogle() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.loginWithGoogle(role: FlavorConfig.defaultRole);
    if (!mounted) return;
    if (ok) {
      Navigator.pushReplacementNamed(context, _homeRouteFor(auth));
    } else if (auth.error != null) {
      _snack(auth.error!);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return FlavorConfig.isCollector ? _collector(auth) : _household(auth);
  }

  Widget _household(AuthProvider auth) {
    return Scaffold(
      backgroundColor: HouseholdColors.sand,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                SvgPicture.asset(HouseholdAssets.loginHero, height: 210),
                const SizedBox(height: 18),
                Text('Welcome back', style: HouseholdType.hero),
                const SizedBox(height: 8),
                Text('Book a pickup, track collectors, and manage payments from your BinLink home.', style: HouseholdType.body.copyWith(color: HouseholdColors.gray)),
                const SizedBox(height: 28),
                HTextField(controller: _email, label: 'Email', hint: 'name@example.com', keyboardType: TextInputType.emailAddress, validator: Validators.email),
                const SizedBox(height: 14),
                HTextField(controller: _password, label: 'Password', hint: 'Enter password', obscure: true, validator: Validators.password),
                Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pushNamed(context, '/forgot-password'), child: Text('Forgot password?', style: HouseholdType.caption.copyWith(color: HouseholdColors.primary, fontWeight: FontWeight.w700)))),
                const SizedBox(height: 12),
                HButton(label: 'Continue', icon: 'security', loading: auth.loading, onPressed: _loginEmail),
                const SizedBox(height: 12),
                HButton(label: 'Continue with Google', icon: 'search', secondary: true, onPressed: _loginGoogle),
                const SizedBox(height: 22),
                Center(child: TextButton(onPressed: () => Navigator.pushNamed(context, '/register'), child: Text('Create a BinLink account', style: HouseholdType.body.copyWith(color: HouseholdColors.forest, fontWeight: FontWeight.w700)))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _collector(AuthProvider auth) {
    return Scaffold(
      backgroundColor: CollectorColors.dark,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 18),
                SvgPicture.asset(CollectorAssets.logo, width: 220),
                const SizedBox(height: 36),
                Text('Collector login', style: CollectorType.hero),
                const SizedBox(height: 10),
                Text('Go online, accept jobs, navigate routes, and close pickups from the field cockpit.', style: CollectorType.body.copyWith(color: const Color(0xFFC8D0DA))),
                const SizedBox(height: 32),
                CTextField(controller: _email, label: 'Email', hint: 'collector@example.com', keyboardType: TextInputType.emailAddress, validator: Validators.email),
                const SizedBox(height: 14),
                CTextField(controller: _password, label: 'Password', hint: 'Enter password', obscure: true, validator: Validators.password),
                Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pushNamed(context, '/forgot-password'), child: Text('Reset password', style: CollectorType.caption.copyWith(color: CollectorColors.green)))),
                const SizedBox(height: 14),
                CButton(label: 'SIGN IN', icon: 'security', loading: auth.loading, onPressed: _loginEmail),
                const SizedBox(height: 12),
                CButton(label: 'SIGN IN WITH GOOGLE', icon: 'scan', secondary: true, onPressed: _loginGoogle),
                const SizedBox(height: 24),
                Center(child: TextButton(onPressed: () => Navigator.pushNamed(context, '/register'), child: Text('Register as a collector', style: CollectorType.body.copyWith(color: CollectorColors.green, fontWeight: FontWeight.w800)))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
