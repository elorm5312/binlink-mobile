import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_flavor.dart';
import '../../../core/design_system/collector_design_system.dart';
import '../../../core/design_system/household_design_system.dart';
import '../../../core/utils/validators.dart';
import '../providers/auth_provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = await auth.registerWithEmail(
      email: _email.text.trim(),
      password: _password.text,
      fullName: _name.text.trim(),
      phone: _phone.text.trim(),
      role: FlavorConfig.defaultRole,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pushReplacementNamed(context, FlavorConfig.isCollector ? '/collector' : '/household');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error ?? 'Registration failed'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  String? _confirmValidator(String? v) {
    if (v == null || v.isEmpty) return 'Please confirm your password';
    if (v != _password.text) return 'Passwords do not match';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return FlavorConfig.isCollector ? _collector(auth) : _household(auth);
  }

  Widget _household(AuthProvider auth) => Scaffold(
        backgroundColor: HouseholdColors.sand,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                IconButton(onPressed: () => Navigator.maybePop(context), icon: HIcon('route', color: HouseholdColors.forest)),
                SvgPicture.asset(HouseholdAssets.registerHero, height: 190),
                const SizedBox(height: 16),
                Text('Create your account', style: HouseholdType.hero),
                const SizedBox(height: 8),
                Text(FlavorConfig.registerSubtitle, style: HouseholdType.body.copyWith(color: HouseholdColors.gray)),
                const SizedBox(height: 24),
                HTextField(controller: _name, label: 'Full name', hint: 'Ama Mensah', validator: Validators.required),
                const SizedBox(height: 12),
                HTextField(controller: _email, label: 'Email', hint: 'name@example.com', keyboardType: TextInputType.emailAddress, validator: Validators.email),
                const SizedBox(height: 12),
                HTextField(controller: _phone, label: 'Phone', hint: '024XXXXXXX', keyboardType: TextInputType.phone, validator: Validators.phone),
                const SizedBox(height: 12),
                HTextField(controller: _password, label: 'Password', obscure: true, validator: Validators.password),
                const SizedBox(height: 12),
                HTextField(controller: _confirm, label: 'Confirm password', obscure: true, validator: _confirmValidator),
                const SizedBox(height: 22),
                HButton(label: 'Create account', icon: 'profile', loading: auth.loading, onPressed: _register),
                const SizedBox(height: 18),
                Center(child: TextButton(onPressed: () => Navigator.maybePop(context), child: Text('Already have an account? Sign in', style: HouseholdType.body.copyWith(color: HouseholdColors.forest, fontWeight: FontWeight.w700)))),
              ]),
            ),
          ),
        ),
      );

  Widget _collector(AuthProvider auth) => Scaffold(
        backgroundColor: CollectorColors.dark,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                IconButton(onPressed: () => Navigator.maybePop(context), icon: CIcon('route', color: CollectorColors.white)),
                SvgPicture.asset(CollectorAssets.welcome, height: 190),
                const SizedBox(height: 20),
                Text('Collector registration', style: CollectorType.hero),
                const SizedBox(height: 10),
                Text('Set up your field profile for verified pickup work across Ghana.', style: CollectorType.body.copyWith(color: const Color(0xFFC8D0DA))),
                const SizedBox(height: 26),
                CTextField(controller: _name, label: 'Full name', hint: 'Kojo Addo', validator: Validators.required),
                const SizedBox(height: 12),
                CTextField(controller: _email, label: 'Email', hint: 'collector@example.com', keyboardType: TextInputType.emailAddress, validator: Validators.email),
                const SizedBox(height: 12),
                CTextField(controller: _phone, label: 'Phone', hint: '024XXXXXXX', keyboardType: TextInputType.phone, validator: Validators.phone),
                const SizedBox(height: 12),
                CTextField(controller: _password, label: 'Password', obscure: true, validator: Validators.password),
                const SizedBox(height: 12),
                CTextField(controller: _confirm, label: 'Confirm password', obscure: true, validator: _confirmValidator),
                const SizedBox(height: 22),
                CButton(label: 'CREATE COLLECTOR ACCOUNT', icon: 'profile', loading: auth.loading, onPressed: _register),
                const SizedBox(height: 18),
                Center(child: TextButton(onPressed: () => Navigator.maybePop(context), child: Text('Already registered? Sign in', style: CollectorType.body.copyWith(color: CollectorColors.green, fontWeight: FontWeight.w800)))),
              ]),
            ),
          ),
        ),
      );
}
