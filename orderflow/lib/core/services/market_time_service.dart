import 'package:intl/intl.dart';
import '../constants/app_constants.dart';

class MarketTimeService {
  /// Returns the current time in IST (UTC+5:30)
  static DateTime getISTNow() {
    return DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
  }

  /// Checks if the market is currently open based on IST time
  static bool isMarketOpen() {
    final nowIST = getISTNow();
    
    // Check if it's a weekend (Saturday = 6, Sunday = 7)
    if (nowIST.weekday == DateTime.saturday || nowIST.weekday == DateTime.sunday) {
      return false;
    }

    // Parse market hours from constants
    final format = DateFormat('HH:mm');
    final openTime = format.parse(AppConstants.marketOpenTime);
    final closeTime = format.parse(AppConstants.marketCloseTime);

    final currentTime = DateTime(0, 1, 1, nowIST.hour, nowIST.minute);
    final marketOpen = DateTime(0, 1, 1, openTime.hour, openTime.minute);
    final marketClose = DateTime(0, 1, 1, closeTime.hour, closeTime.minute);

    return currentTime.isAfter(marketOpen) && currentTime.isBefore(marketClose);
  }

  /// Returns total seconds remaining in the current 5-minute candle
  static int getRemainingSecondsInCandle() {
    final nowIST = getISTNow();
    final secondsInCurCandle = (nowIST.minute % 5) * 60 + nowIST.second;
    return 300 - secondsInCurCandle;
  }
}
