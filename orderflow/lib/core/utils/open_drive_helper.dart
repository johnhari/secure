import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../../data/models/candle_model.dart';

/// Helper utility for Open Drive ("OD") trading pattern detection & strict retest validation.
///
/// User Directive Rules:
/// 1. Bullish OD: Open = Low at 09:15 AM.
/// 2. Bearish OD: Open = High at 09:15 AM.
/// 3. Retest Disqualification Rule:
///    - If at any time during the first 1 hour (between 09:15 and <= 10:15 AM, e.g. at 09:55 AM),
///      the price retests/touches back to the initial Open price level,
///      IT IS NOT AN OD STOCK (Disqualified as invalid OD stock!).
/// 4. Pure Unbroken Drive:
///    - Bullish OD: Price moved up from Open and NEVER retested back down to Open.
///    - Bearish OD: Price moved down from Open and NEVER retested back up to Open.
class OpenDriveHelper {
  /// Evaluates if an OHLC data point represents a valid, UNBROKEN Open Drive (OD) stock.
  static bool isOpenDriveValid({
    required double open,
    required double high,
    required double low,
    required double close,
    bool isRetestedBefore1015 = false,
    DateTime? candleTime,
    DateTime? currentTime,
  }) {
    if (open <= 0) return false;

    // Strict Retest Disqualification: If retested at 09:55 or <= 10:15 AM, NOT OD!
    if (isRetestedBefore1015) return false;

    // Tolerance factor for exchange tick noise (0.05%)
    const double tolerance = 0.0005;

    final bool isOpenLow = (low - open).abs() / open <= tolerance;
    final bool isOpenHigh = (high - open).abs() / open <= tolerance;

    if (!isOpenLow && !isOpenHigh) return false;

    // Bullish OD (Open = Low): Price must move UP and NOT retest back down to Open level
    if (isOpenLow) {
      if (low < open || (close - open) / open < tolerance) {
        return false;
      }
    }

    // Bearish OD (Open = High): Price must move DOWN and NOT retest back up to Open level
    if (isOpenHigh) {
      if (high > open || (open - close) / open < tolerance) {
        return false;
      }
    }

    // 1-Hour Window Check (09:15 to 10:15 AM)
    final now = currentTime ?? DateTime.now();
    if (candleTime != null) {
      final oneHourMark = DateTime(candleTime.year, candleTime.month, candleTime.day, 10, 15);
      
      // Past 10:15 AM check: Ensure no retest occurred in the 09:15 - 10:15 AM window
      if (now.isAfter(oneHourMark) || now.day != candleTime.day) {
        if (isOpenLow && low <= open * 1.0002) return false; // Retested open -> NOT OD
        if (isOpenHigh && high >= open * 0.9998) return false; // Retested open -> NOT OD
      }
    }

    return true;
  }

  /// Evaluates a full session of 5-minute candles to confirm an unbroken Open Drive (OD) stock.
  /// Returns FALSE if the stock retested the Open price at 09:55 AM or anytime <= 10:15 AM.
  static bool isSeriesUnbrokenOpenDrive(List<CandleModel> dayCandles) {
    if (dayCandles.isEmpty) return false;

    final firstCandle = dayCandles.first; // 09:15 AM candle
    final double dayOpen = firstCandle.open;
    if (dayOpen <= 0) return false;

    const double tolerance = 0.0005;
    final bool isOpenLow = (firstCandle.low - dayOpen).abs() / dayOpen <= tolerance;
    final bool isOpenHigh = (firstCandle.high - dayOpen).abs() / dayOpen <= tolerance;

    if (!isOpenLow && !isOpenHigh) return false;

    // Inspect candles during the 1-hour window (09:20 AM to 10:15 AM)
    for (int i = 1; i < dayCandles.length; i++) {
      final c = dayCandles[i];
      final time = c.timeStart;
      
      // Only inspect candles up to 10:15 AM
      final isFirstHour = (time.hour == 9 && time.minute >= 20) || (time.hour == 10 && time.minute <= 15);
      if (isFirstHour) {
        if (isOpenLow) {
          // If low touched or dropped back to dayOpen -> RETEST OCCURRED -> NOT OD!
          if (c.low <= dayOpen * 1.0002) return false;
        } else if (isOpenHigh) {
          // If high touched or climbed back to dayOpen -> RETEST OCCURRED -> NOT OD!
          if (c.high >= dayOpen * 0.9998) return false;
        }
      }
    }

    return true;
  }

  /// Returns OD pattern type label ('OPEN=LOW' or 'OPEN=HIGH') or null if not OD.
  static String? getOpenDriveLabel({
    required double open,
    required double high,
    required double low,
    required double close,
  }) {
    if (open <= 0) return null;
    const double tolerance = 0.0005;
    final bool isOpenLow = (low - open).abs() / open <= tolerance;
    final bool isOpenHigh = (high - open).abs() / open <= tolerance;

    if (isOpenLow && close >= open) return 'OPEN=LOW (BUY)';
    if (isOpenHigh && close <= open) return 'OPEN=HIGH (SELL)';
    return null;
  }

  /// Returns tag color for OD badge
  static Color getOpenDriveColor({
    required double open,
    required double high,
    required double low,
    required double close,
  }) {
    const double tolerance = 0.0005;
    final bool isOpenLow = (low - open).abs() / open <= tolerance;
    if (isOpenLow) return AppTheme.bullColor;
    return AppTheme.bearColor;
  }
}
