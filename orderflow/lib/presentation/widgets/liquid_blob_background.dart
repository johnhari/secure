import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class LiquidBlobBackground extends StatefulWidget {
  const LiquidBlobBackground({super.key});

  @override
  State<LiquidBlobBackground> createState() => _LiquidBlobBackgroundState();
}

class _LiquidBlobBackgroundState extends State<LiquidBlobBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Slow animation for the liquid blobs (25 seconds loop)
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 25),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = size.width;
    final height = size.height;

    return Stack(
      children: [
        // Solid background base
        Container(
          color: AppTheme.bgColor,
        ),
        // Animated Blobs layer — using RadialGradient for soft glow (no GPU blur)
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = _controller.value * 2 * pi;

            // Compute floating positions for 3 organic blobs
            final blob1X = width * 0.7 + 70 * cos(t);
            final blob1Y = height * 0.15 + 90 * sin(t);

            final blob2X = width * 0.15 + 90 * sin(t * 1.2);
            final blob2Y = height * 0.8 + 80 * cos(t * 0.8);

            final blob3X = width * 0.8 + 80 * cos(t * 0.6);
            final blob3Y = height * 0.65 + 70 * sin(t * 1.1);

            return Stack(
              children: [
                // Blob 1: Cyan
                Positioned(
                  left: blob1X - 150,
                  top: blob1Y - 150,
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppTheme.primaryCyan.withValues(alpha: 0.12),
                          AppTheme.primaryCyan.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                // Blob 2: Purple
                Positioned(
                  left: blob2X - 180,
                  top: blob2Y - 180,
                  child: Container(
                    width: 360,
                    height: 360,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppTheme.accentPurple.withValues(alpha: 0.10),
                          AppTheme.accentPurple.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                // Blob 3: Gold/Amber
                Positioned(
                  left: blob3X - 130,
                  top: blob3Y - 130,
                  child: Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppTheme.goldColor.withValues(alpha: 0.08),
                          AppTheme.goldColor.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        // No full-screen BackdropFilter — RadialGradient on each blob handles the soft glow
      ],
    );
  }
}
