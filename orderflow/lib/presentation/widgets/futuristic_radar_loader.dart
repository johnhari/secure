import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class FuturisticRadarLoader extends StatefulWidget {
  final double size;
  final String? statusText;
  final bool showProgressText;

  const FuturisticRadarLoader({
    super.key,
    this.size = 140,
    this.statusText,
    this.showProgressText = true,
  });

  @override
  State<FuturisticRadarLoader> createState() => _FuturisticRadarLoaderState();
}

class _FuturisticRadarLoaderState extends State<FuturisticRadarLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Outer Glow Aura
                  Container(
                    width: size * 0.9,
                    height: size * 0.9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppTheme.primaryCyan.withValues(alpha: 0.18 + (math.sin(_controller.value * math.pi * 2) * 0.08)),
                          AppTheme.accentPurple.withValues(alpha: 0.10),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.6, 1.0],
                      ),
                    ),
                  ),

                  // Custom Cyber Radar Rings
                  CustomPaint(
                    size: Size(size, size),
                    painter: _RadarPainter(
                      progress: _controller.value,
                    ),
                  ),

                  // Center Pulsing Quantum Core Orb
                  Transform.scale(
                    scale: 0.85 + (math.sin(_controller.value * math.pi * 2) * 0.15),
                    child: Container(
                      width: size * 0.22,
                      height: size * 0.22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          colors: [
                            Colors.white,
                            AppTheme.primaryCyan,
                            AppTheme.accentPurple,
                          ],
                          stops: [0.2, 0.6, 1.0],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryCyan.withValues(alpha: 0.8),
                            blurRadius: 16,
                            spreadRadius: 3,
                          ),
                          BoxShadow(
                            color: AppTheme.accentPurple.withValues(alpha: 0.5),
                            blurRadius: 24,
                            spreadRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        if (widget.statusText != null) ...[
          const SizedBox(height: 20),
          Text(
            widget.statusText!,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
              shadows: [
                Shadow(
                  color: AppTheme.primaryCyan.withValues(alpha: 0.6),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;

  _RadarPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;

    final double rotation = progress * math.pi * 2;
    final double counterRotation = -progress * math.pi * 3;

    // 1. Outer Tech Dashed Track
    final outerTrackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius * 0.92, outerTrackPaint);

    // Outer Dashed Segments
    final dashPaint = Paint()
      ..color = AppTheme.primaryCyan.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    const int totalDashCount = 16;
    for (int i = 0; i < totalDashCount; i++) {
      final angle = (i * (2 * math.pi / totalDashCount)) + (rotation * 0.3);
      final dx1 = center.dx + (radius * 0.88) * math.cos(angle);
      final dy1 = center.dy + (radius * 0.88) * math.sin(angle);
      final dx2 = center.dx + (radius * 0.94) * math.cos(angle);
      final dy2 = center.dy + (radius * 0.94) * math.sin(angle);
      canvas.drawLine(Offset(dx1, dy1), Offset(dx2, dy2), dashPaint);
    }

    // 2. Outer Rotating Gradient Arc
    final outerArcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.0
      ..shader = SweepGradient(
        transform: GradientRotation(rotation),
        colors: const [
          Colors.transparent,
          AppTheme.primaryCyan,
          AppTheme.accentPurple,
          AppTheme.goldColor,
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 0.65, 0.85, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.90),
      rotation,
      math.pi * 1.35,
      false,
      outerArcPaint,
    );

    // 3. Inner Counter-Rotating Cyber Arc
    final innerArcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.0
      ..shader = SweepGradient(
        transform: GradientRotation(counterRotation),
        colors: const [
          Colors.transparent,
          Color(0xFF00E5FF),
          Color(0xFFE040FB),
          Colors.transparent,
        ],
        stops: const [0.0, 0.4, 0.8, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.68));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.68),
      counterRotation,
      math.pi * 1.1,
      false,
      innerArcPaint,
    );

    // 4. Inner Ring Track
    final innerTrackPaint = Paint()
      ..color = AppTheme.primaryCyan.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, radius * 0.68, innerTrackPaint);

    // 5. Radar Sweep Beam Line
    final sweepAngle = rotation * 1.5;
    final sweepLinePaint = Paint()
      ..shader = LinearGradient(
        colors: [
          AppTheme.primaryCyan.withValues(alpha: 0.8),
          Colors.transparent,
        ],
      ).createShader(Rect.fromPoints(
        center,
        Offset(
          center.dx + radius * 0.90 * math.cos(sweepAngle),
          center.dy + radius * 0.90 * math.sin(sweepAngle),
        ),
      ))
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      center,
      Offset(
        center.dx + radius * 0.90 * math.cos(sweepAngle),
        center.dy + radius * 0.90 * math.sin(sweepAngle),
      ),
      sweepLinePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
