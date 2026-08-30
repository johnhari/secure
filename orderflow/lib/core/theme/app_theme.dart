import 'package:flutter/material.dart';

class AppTheme {
  // --- COLOR PALETTE ---
  static const Color bgColor = Color(0xFF131722); // TradingView Deep Charcoal
  static const Color cardColor = Color(0xFF1E222D);
  static const Color glassColor = Color(0x1AFFFFFF); // 10% white for glass
  
  static const Color primaryCyan = Color(0xFF2962FF); // TradingView Blue
  static const Color accentPurple = Color(0xFF764BA2);
  
  static const Color bullColor = Color(0xFF089981); // TradingView Emerald
  static const Color bearColor = Color(0xFFF23645); // TradingView Tomato
  static const Color gridColor = Color(0xFF2A2E39); // TradingView Grid
  static const Color errorColor = bearColor; 
  static const Color goldColor = Color(0xFFFFD700); 

  static const Color textColor = Color(0xFFFFFFFF);
  static const Color subTextColor = Color(0xFF94A3B8);
  static const Color dimTextColor = Color(0xFF475569);

  // --- TEXT STYLES ---
  static const TextStyle headingStyle = TextStyle(
    color: textColor,
    fontSize: 24,
    fontWeight: FontWeight.w900,
    letterSpacing: 1.2,
  );

  static const TextStyle subHeadingStyle = TextStyle(
    color: subTextColor,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

  static const TextStyle bodyStyle = TextStyle(
    color: textColor,
    fontSize: 13,
    fontWeight: FontWeight.w400,
  );

  // --- GLASSMORPHISM UTILITIES ---
  static BoxDecoration glassDecoration({
    double blur = 16.0,
    double opacity = 0.07,
    BorderRadius? borderRadius,
    Color borderColor = const Color(0x26FFFFFF), // white with 15% opacity
  }) {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: opacity),
      borderRadius: borderRadius ?? BorderRadius.circular(16),
      border: Border.all(color: borderColor, width: 1.0),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.4),
          blurRadius: 24,
          spreadRadius: -4,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.02),
          blurRadius: 1,
          spreadRadius: 0,
          offset: const Offset(0, 1),
        ),
      ],
    );
  }

  static BoxDecoration neonGlassDecoration({
    required Color glowColor,
    double opacity = 0.06,
    BorderRadius? borderRadius,
    double borderWidth = 1.0,
  }) {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: opacity),
      borderRadius: borderRadius ?? BorderRadius.circular(16),
      border: Border.all(color: glowColor.withValues(alpha: 0.35), width: borderWidth),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.4),
          blurRadius: 24,
          spreadRadius: -4,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: glowColor.withValues(alpha: 0.15),
          blurRadius: 14,
          spreadRadius: -2,
        ),
      ],
    );
  }

  static BoxDecoration neonGlow(Color color, {double blur = 8.0, double spread = 1.0}) {
    return BoxDecoration(
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: 0.4),
          blurRadius: blur,
          spreadRadius: spread,
        ),
      ],
    );
  }

  // --- THEME DATA ---
  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: bgColor,
      primaryColor: primaryCyan,
      cardColor: cardColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryCyan, width: 2),
        ),
        labelStyle: const TextStyle(color: subTextColor),
        hintStyle: const TextStyle(color: dimTextColor),
      ),
    );
  }
}
