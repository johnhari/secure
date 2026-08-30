import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../providers/auth_provider.dart';
import 'chart_screen.dart';
import 'risk_disclosure_screen.dart';
import 'login_screen.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/futuristic_radar_loader.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _glowController;
  late AnimationController _rotationController;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _glowAnimation;
  
  bool _isNavigating = false;
  bool _showRiskDisclosure = false;

  @override
  void initState() {
    super.initState();
    
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _logoScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: const Interval(0.0, 0.5, curve: Curves.easeIn)),
    );

    _glowAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _logoController.forward();
    _initializeApp();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _glowController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    // 1. Minimum splash time for "WOW" effect
    await Future.delayed(const Duration(milliseconds: 1200));
    
    if (!mounted) return;

    // 2. Check if Risk Disclosure was already accepted
    bool hasAcceptedRisk = false;
    try {
      final box = await Hive.openBox('settings');
      hasAcceptedRisk = box.get('hasAcceptedRisk', defaultValue: false);
    } catch (e) {
      debugPrint('[SPLASH] Hive settings box error: $e');
    }

    final bool isDesktop = !kIsWeb && (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.linux);
    if (isDesktop || !hasAcceptedRisk) {
      // Persist risk acceptance
      try {
        final box = await Hive.openBox('settings');
        await box.put('hasAcceptedRisk', true);
      } catch (_) {}
      
      if (!isDesktop && !hasAcceptedRisk) {
        if (mounted) {
          setState(() {
            _showRiskDisclosure = true;
          });
        }
        return;
      }
    }

    // 3. Automated Auth/Guest handling
    _proceedToTerminal();
  }

  void _safeNavigateTo(Widget screen, {required int durationMs, bool isFallback = false}) {
    if (!mounted) return;
    if (isFallback) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => screen),
      );
    } else {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => screen,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: Duration(milliseconds: durationMs),
        ),
      );
    }
  }

  Future<void> _proceedToTerminal() async {
    if (_isNavigating) return;
    _isNavigating = true;

    try {
      // Wait for Auth Provider to settle
      int attempts = 0;
      while (attempts < 30) { // 3 seconds max
        try {
          final authState = ref.read(authProvider);
          if (authState.status != AuthStatus.initial && authState.status != AuthStatus.loading) {
            if (authState.status == AuthStatus.unauthenticated) {
              debugPrint('[SPLASH] Access unauthenticated. Navigating to LoginScreen');
              _safeNavigateTo(const LoginScreen(), durationMs: 800);
              return;
            }
            
            // If authenticated, go to chart
            _safeNavigateTo(const ChartScreen(), durationMs: 800);
            return;
          }
        } catch (e) {
          debugPrint('[SPLASH] Error polling authProvider: $e');
          // If we hit an authentication crash, break out of loop immediately and fallback
          break;
        }
        
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }
    } catch (globalError) {
      debugPrint('[SPLASH] Global error in _proceedToTerminal: $globalError');
    }
 
    // Fallback: Force navigation to Login if auth hangs or crashes
    debugPrint('[SPLASH] Auth timeout or crash - forcing login navigation');
    _safeNavigateTo(const LoginScreen(), durationMs: 0, isFallback: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_showRiskDisclosure) {
      return RiskDisclosureScreen(
        onAccepted: () async {
          try {
            final sBox = await Hive.openBox('settings');
            await sBox.put('hasAcceptedRisk', true);
          } catch (e) {
            debugPrint('[SPLASH] Error saving hasAcceptedRisk: $e');
          }
          
          if (mounted) {
            setState(() {
              _showRiskDisclosure = false;
            });
            _proceedToTerminal();
          }
        },
      );
    }

    final size = MediaQuery.of(context).size;
    final double scaleFactor = (size.width / 390).clamp(1.0, 1.5);

    return Scaffold(
      backgroundColor: const Color(0xFF060B12), // Deep premium dark
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Background Glow
          AnimatedBuilder(
            animation: _glowAnimation,
            builder: (context, child) {
              return Container(
                width: size.width,
                height: size.height,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.8,
                    colors: [
                      AppTheme.primaryCyan.withValues(alpha: 0.15 * _glowAnimation.value),
                      Colors.transparent,
                    ],
                  ),
                ),
              );
            },
          ),
          
          // Centered Logo & Brand
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: Listenable.merge([_logoController, _glowController, _rotationController]),
                builder: (context, child) {
                  return Opacity(
                    opacity: _logoOpacity.value,
                    child: Transform.scale(
                      scale: _logoScale.value,
                      child: SizedBox(
                        width: 190 * scaleFactor,
                        height: 190 * scaleFactor,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outer Rotating Cyber Ring
                            RotationTransition(
                              turns: _rotationController,
                              child: Container(
                                width: 185 * scaleFactor,
                                height: 185 * scaleFactor,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: SweepGradient(
                                    colors: [
                                      AppTheme.primaryCyan.withValues(alpha: 0.8),
                                      AppTheme.goldColor.withValues(alpha: 0.6),
                                      AppTheme.accentPurple.withValues(alpha: 0.4),
                                      AppTheme.primaryCyan.withValues(alpha: 0.8),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Counter-rotating Inner Ring
                            RotationTransition(
                              turns: ReverseAnimation(_rotationController),
                              child: Container(
                                width: 165 * scaleFactor,
                                height: 165 * scaleFactor,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppTheme.goldColor.withValues(alpha: 0.4),
                                    width: 1.2,
                                  ),
                                ),
                              ),
                            ),

                            // Core Glow Shadow & Logo
                            Container(
                              width: 145 * scaleFactor,
                              height: 145 * scaleFactor,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF0D121F),
                                border: Border.all(
                                  color: AppTheme.primaryCyan.withValues(alpha: 0.6),
                                  width: 2.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.primaryCyan.withValues(alpha: 0.35 * _glowAnimation.value),
                                    blurRadius: 35 * scaleFactor,
                                    spreadRadius: 6 * scaleFactor,
                                  ),
                                  BoxShadow(
                                    color: AppTheme.goldColor.withValues(alpha: 0.2 * _glowAnimation.value),
                                    blurRadius: 50 * scaleFactor,
                                    spreadRadius: 2 * scaleFactor,
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Image.asset(
                                    'assets/images/logo.png',
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) => Icon(
                                      Icons.auto_graph_rounded,
                                      size: 70 * scaleFactor,
                                      color: AppTheme.primaryCyan,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              FadeTransition(
                opacity: _logoOpacity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Most Advance Orderflow Analyzer',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22 * scaleFactor,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          shadows: [
                            Shadow(
                              color: AppTheme.primaryCyan.withValues(alpha: 0.5),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ADVANCED ORDERFLOW TERMINAL',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.primaryCyan.withValues(alpha: 0.7),
                          fontSize: 12 * scaleFactor,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            ],
          ),
          
          // Loading Indicator at bottom
          Positioned(
            bottom: 70,
            child: FadeTransition(
              opacity: _logoOpacity,
              child: const FuturisticRadarLoader(
                size: 55,
                showProgressText: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
