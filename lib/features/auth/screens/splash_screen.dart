import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/app_flavor.dart';
import '../providers/auth_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _shimmerCtrl;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _shimmerAnim;
  late final Animation<double> _fadeAnim;

  // Flavor-based colors
  bool get _isCollector => FlavorConfig.isCollector;

  // Collector: dark theme, Household: light theme
  Color get _bgColor => _isCollector ? const Color(0xFF0B100D) : const Color(0xFFF4F7F4);
  Color get _accentColor => const Color(0xFF2BD97B);
  Color get _accentDark => const Color(0xFF16A34A);
  Color get _mutedTextColor => _isCollector ? Colors.white.withAlpha(150) : const Color(0xFF6B7280);
  Color get _glowColor => _isCollector ? _accentColor : _accentDark;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
    _shimmerAnim = Tween<double>(begin: -1.5, end: 1.5).animate(
      CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut),
    );

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    // Set system UI based on flavor
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: _isCollector ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: _bgColor,
      systemNavigationBarIconBrightness: _isCollector ? Brightness.light : Brightness.dark,
    ));

    _init();
  }

  Future<void> _init() async {
    await Future.wait([
      context.read<AuthProvider>().initialize(),
      Future.delayed(const Duration(milliseconds: 800)),
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
    Navigator.pushReplacementNamed(
        context, (prefs.getBool('show_onboarding') ?? true) ? '/onboarding' : '/login');
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _shimmerCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: Stack(
        children: [
          // Animated gradient background
          _AnimatedGradientBackground(
            shimmerAnim: _shimmerAnim,
            isCollector: _isCollector,
          ),

          // Floating particles effect
          _FloatingParticles(isCollector: _isCollector),

          // Main content
          FadeTransition(
            opacity: _fadeAnim,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo with glow effect
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (context, child) {
                      return Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _glowColor.withAlpha((60 * _pulseAnim.value).round()),
                              blurRadius: 80,
                              spreadRadius: 20,
                            ),
                            BoxShadow(
                              color: _accentDark.withAlpha((40 * _pulseAnim.value).round()),
                              blurRadius: 120,
                              spreadRadius: 40,
                            ),
                          ],
                        ),
                        child: child,
                      );
                    },
                    child: _buildLogo(),
                  ),

                  const SizedBox(height: 40),

                  // App name with shimmer
                  _ShimmerText(
                    text: 'BinLink Eco',
                    shimmerAnim: _shimmerAnim,
                    isCollector: _isCollector,
                  ),

                  const SizedBox(height: 8),

                  // Tagline
                  Text(
                    _isCollector ? 'COLLECTOR' : 'Smart Waste Collection',
                    style: TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _mutedTextColor,
                      letterSpacing: _isCollector ? 4 : 2,
                    ),
                  ),

                  const SizedBox(height: 50),

                  // Loading indicator
                  _GlassLoadingIndicator(
                    pulseAnim: _pulseAnim,
                    isCollector: _isCollector,
                  ),
                ],
              ),
            ),
          ),

          // Bottom branding
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Column(
                children: [
                  Text(
                    'Powered by',
                    style: TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: 10,
                      color: _mutedTextColor.withAlpha(120),
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'BinLink Eco Ghana',
                    style: TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _accentColor,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return SizedBox(
      width: 180,
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer container
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _isCollector
                    ? [const Color(0xFF1A2A1F), const Color(0xFF0D1510)]
                    : [Colors.white, const Color(0xFFE8F5EC)],
              ),
              border: Border.all(
                color: _accentColor.withAlpha(60),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: _isCollector
                      ? Colors.black.withAlpha(100)
                      : _accentDark.withAlpha(30),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
          ),
          // Lottie animation
          Lottie.asset(
            'assets/shared/lottie/splash_animation.json',
            width: 180,
            height: 180,
            fit: BoxFit.contain,
          ),
          // Center icon
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [_accentColor, _accentDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds),
            child: Icon(
              _isCollector ? Icons.local_shipping_rounded : Icons.recycling_rounded,
              size: 50,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// Animated gradient background with moving light effect
class _AnimatedGradientBackground extends StatelessWidget {
  const _AnimatedGradientBackground({
    required this.shimmerAnim,
    required this.isCollector,
  });
  final Animation<double> shimmerAnim;
  final bool isCollector;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shimmerAnim,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(shimmerAnim.value * 0.5, -0.3),
              radius: 1.5,
              colors: isCollector
                  ? const [
                      Color(0xFF1A2E1F),
                      Color(0xFF0F1A12),
                      Color(0xFF0B100D),
                    ]
                  : const [
                      Color(0xFFE8F5EC),
                      Color(0xFFF0F7F2),
                      Color(0xFFF4F7F4),
                    ],
              stops: const [0.0, 0.4, 1.0],
            ),
          ),
        );
      },
    );
  }
}

// Floating particles effect
class _FloatingParticles extends StatefulWidget {
  const _FloatingParticles({required this.isCollector});
  final bool isCollector;

  @override
  State<_FloatingParticles> createState() => _FloatingParticlesState();
}

class _FloatingParticlesState extends State<_FloatingParticles>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    final random = math.Random();
    _particles = List.generate(20, (i) => _Particle(
      x: random.nextDouble(),
      y: random.nextDouble(),
      size: 2 + random.nextDouble() * 4,
      speed: 0.2 + random.nextDouble() * 0.5,
      opacity: 0.1 + random.nextDouble() * 0.3,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: MediaQuery.of(context).size,
          painter: _ParticlesPainter(
            particles: _particles,
            progress: _controller.value,
            isCollector: widget.isCollector,
          ),
        );
      },
    );
  }
}

class _Particle {
  final double x;
  final double y;
  final double size;
  final double speed;
  final double opacity;

  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.opacity,
  });
}

class _ParticlesPainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;
  final bool isCollector;

  _ParticlesPainter({
    required this.particles,
    required this.progress,
    required this.isCollector,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final color = isCollector
        ? const Color(0xFF2BD97B)
        : const Color(0xFF16A34A);
    for (final p in particles) {
      final y = (p.y + progress * p.speed) % 1.0;
      final paint = Paint()
        ..color = color.withAlpha((p.opacity * 255).round())
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawCircle(
        Offset(p.x * size.width, y * size.height),
        p.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// Shimmer text effect
class _ShimmerText extends StatelessWidget {
  const _ShimmerText({
    required this.text,
    required this.shimmerAnim,
    required this.isCollector,
  });
  final String text;
  final Animation<double> shimmerAnim;
  final bool isCollector;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shimmerAnim,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(shimmerAnim.value - 0.3, 0),
              end: Alignment(shimmerAnim.value + 0.3, 0),
              colors: isCollector
                  ? const [Color(0xFF2BD97B), Colors.white, Color(0xFF2BD97B)]
                  : const [Color(0xFF16A34A), Color(0xFF2BD97B), Color(0xFF16A34A)],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'PlusJakartaSans',
          fontSize: 36,
          fontWeight: FontWeight.w900,
          color: isCollector ? Colors.white : const Color(0xFF0B3B2E),
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

// Glass loading indicator
class _GlassLoadingIndicator extends StatelessWidget {
  const _GlassLoadingIndicator({
    required this.pulseAnim,
    required this.isCollector,
  });
  final Animation<double> pulseAnim;
  final bool isCollector;

  @override
  Widget build(BuildContext context) {
    final accentColor = const Color(0xFF2BD97B);
    final textColor = isCollector ? Colors.white : const Color(0xFF0B3B2E);

    return AnimatedBuilder(
      animation: pulseAnim,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            color: isCollector
                ? Colors.white.withAlpha(8)
                : const Color(0xFF16A34A).withAlpha(15),
            border: Border.all(
              color: accentColor.withAlpha(isCollector ? 40 : 60),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withAlpha((20 * pulseAnim.value).round()),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(
                        Color.lerp(
                          const Color(0xFF16A34A),
                          const Color(0xFF2BD97B),
                          pulseAnim.value,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Loading...',
                    style: TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textColor.withAlpha(180),
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
