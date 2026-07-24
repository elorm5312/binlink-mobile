import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_flavor.dart';
import '../../../core/design_system/collector_design_system.dart';
import '../../../core/design_system/household_design_system.dart';
import '../../../core/utils/validators.dart';
import '../providers/auth_provider.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await context.read<AuthProvider>().sendPasswordReset(_email.text.trim());
    if (mounted) setState(() => _sent = ok);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final collector = FlavorConfig.isCollector;
    return Scaffold(
      backgroundColor: collector ? CollectorColors.dark : HouseholdColors.sand,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconButton(onPressed: () => Navigator.maybePop(context), icon: collector ? CIcon('route', color: CollectorColors.white) : HIcon('route', color: HouseholdColors.forest)),
              const SizedBox(height: 18),
              Builder(builder: (_) {
                final asset = collector ? CollectorAssets.noJobs : HouseholdAssets.forgotPassword;
                return asset.endsWith('.svg') ? SvgPicture.asset(asset, height: 220) : Image.asset(asset, height: 220, fit: BoxFit.contain);
              }),
              const SizedBox(height: 24),
              Text(_sent ? 'Check your inbox' : 'Reset password', style: collector ? CollectorType.hero : HouseholdType.hero),
              const SizedBox(height: 10),
              Text(
                _sent ? 'We sent a reset link to ${_email.text.trim()}.' : 'Enter your account email and we will send a secure reset link.',
                style: collector ? CollectorType.body.copyWith(color: const Color(0xFFC8D0DA)) : HouseholdType.body.copyWith(color: HouseholdColors.gray),
              ),
              const SizedBox(height: 26),
              if (!_sent) ...[
                collector
                    ? CTextField(controller: _email, label: 'Email', hint: 'name@example.com', keyboardType: TextInputType.emailAddress, validator: Validators.email)
                    : HTextField(controller: _email, label: 'Email', hint: 'name@example.com', keyboardType: TextInputType.emailAddress, validator: Validators.email),
                const SizedBox(height: 20),
                collector ? CButton(label: 'SEND RESET LINK', icon: 'security', loading: auth.loading, onPressed: _send) : HButton(label: 'Send reset link', icon: 'security', loading: auth.loading, onPressed: _send),
              ] else
                collector ? CButton(label: 'BACK TO SIGN IN', onPressed: () => Navigator.pushReplacementNamed(context, '/login')) : HButton(label: 'Back to sign in', onPressed: () => Navigator.pushReplacementNamed(context, '/login')),
            ]),
          ),
        ),
      ),
    );
  }
}

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _code = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collector = FlavorConfig.isCollector;
    final args = ModalRoute.of(context)?.settings.arguments;
    final phone = args is Map ? args['phone']?.toString() : null;
    return Scaffold(
      backgroundColor: collector ? CollectorColors.dark : HouseholdColors.sand,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Image.asset(collector ? CollectorAssets.welcome : HouseholdAssets.otpVerify, height: 230, fit: BoxFit.contain),
            const SizedBox(height: 26),
            Text('Verify phone', style: collector ? CollectorType.hero : HouseholdType.hero),
            const SizedBox(height: 10),
            Text(phone == null ? 'No phone verification session is active.' : 'Enter the six digit code sent to $phone.', style: collector ? CollectorType.body.copyWith(color: const Color(0xFFC8D0DA)) : HouseholdType.body.copyWith(color: HouseholdColors.gray)),
            const SizedBox(height: 30),
            TextField(
              controller: _code,
              maxLength: 6,
              keyboardType: TextInputType.number,
              style: collector ? CollectorType.hero : HouseholdType.hero,
              decoration: InputDecoration(
                counterText: '',
                hintText: '000000',
                errorText: _error,
                filled: true,
                fillColor: collector ? CollectorColors.charcoal : HouseholdColors.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
              ),
            ),
            const Spacer(),
            collector
                ? CButton(label: 'VERIFY', loading: _loading, onPressed: phone == null ? null : _verify)
                : HButton(label: 'Verify', loading: _loading, onPressed: phone == null ? null : _verify),
          ]),
        ),
      ),
    );
  }

  Future<void> _verify() async {
    if (_code.text.trim().length != 6) {
      setState(() => _error = 'Enter the 6 digit verification code.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = 'Phone OTP verification is not enabled by the current auth provider.';
    });
  }
}
