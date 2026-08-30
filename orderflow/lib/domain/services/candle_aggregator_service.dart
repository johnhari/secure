import 'dart:async';
import '../../data/models/tick_data_model.dart';
import '../../data/models/candle_model.dart';

class CandleAggregatorService {
  final Map<String, Map<String, CandleModel>> _currentCandles = {}; // timeframe -> symbol -> candle
  final Map<String, StreamController<CandleModel>> _candleControllers = {};
  
  final List<String> _timeframes = ['1m', '5m', '15m', '1H', '1D', '1W'];

  CandleAggregatorService() {
    for (var tf in _timeframes) {
      _candleControllers[tf] = StreamController<CandleModel>.broadcast();
      _currentCandles[tf] = {};
    }
  }

  Stream<CandleModel> getCandleStream(String timeframe) {
    return _candleControllers[timeframe]?.stream ?? const Stream.empty();
  }

  void processTick(TickData tick) {
    for (var tf in _timeframes) {
      _processTickForTimeframe(tick, tf);
    }
  }

  void _processTickForTimeframe(TickData tick, String timeframe) {
    final symbol = tick.instrument;
    final startTime = _getBucketStartTime(tick.timestamp, timeframe);
    final candleKey = '${symbol}_${timeframe}_${startTime.millisecondsSinceEpoch}';
    
    final currentCandle = _currentCandles[timeframe]?[symbol];
    
    if (currentCandle == null || currentCandle.timeStart != startTime) {
      // New candle
      final newCandle = CandleModel(
        symbol: symbol,
        candleKey: candleKey,
        timeStart: startTime,
        timeEnd: _getBucketEndTime(startTime, timeframe),
        open: tick.ltp,
        high: tick.ltp,
        low: tick.ltp,
        close: tick.ltp,
        volume: tick.volume,
      );
      
      _currentCandles[timeframe]?[symbol] = newCandle;
      _candleControllers[timeframe]?.add(newCandle);
    } else {
      // Update existing candle
      final updatedCandle = CandleModel(
        symbol: symbol,
        candleKey: currentCandle.candleKey,
        timeStart: currentCandle.timeStart,
        timeEnd: currentCandle.timeEnd,
        open: currentCandle.open,
        high: tick.ltp > currentCandle.high ? tick.ltp : currentCandle.high,
        low: tick.ltp < currentCandle.low ? tick.ltp : currentCandle.low,
        close: tick.ltp,
        volume: tick.volume, // MO volume is typically cumulative for the day
        buyerCount: currentCandle.buyerCount, // Preserve orderflow if available
        sellerCount: currentCandle.sellerCount,
      );
      
      _currentCandles[timeframe]?[symbol] = updatedCandle;
      _candleControllers[timeframe]?.add(updatedCandle);
    }
  }

  DateTime _getBucketStartTime(DateTime timestamp, String timeframe) {
    switch (timeframe) {
      case '1m':
        return DateTime(timestamp.year, timestamp.month, timestamp.day, timestamp.hour, timestamp.minute);
      case '5m':
        return DateTime(timestamp.year, timestamp.month, timestamp.day, timestamp.hour, (timestamp.minute ~/ 5) * 5);
      case '15m':
        return DateTime(timestamp.year, timestamp.month, timestamp.day, timestamp.hour, (timestamp.minute ~/ 15) * 15);
      case '1H':
        return DateTime(timestamp.year, timestamp.month, timestamp.day, timestamp.hour);
      case '1D':
        return DateTime(timestamp.year, timestamp.month, timestamp.day);
      case '1W':
        int daysToSubtract = (timestamp.weekday - 1);
        return DateTime(timestamp.year, timestamp.month, timestamp.day - daysToSubtract);
      default:
        return timestamp;
    }
  }

  DateTime _getBucketEndTime(DateTime startTime, String timeframe) {
    switch (timeframe) {
      case '1m':
        return startTime.add(const Duration(minutes: 1));
      case '5m':
        return startTime.add(const Duration(minutes: 5));
      case '15m':
        return startTime.add(const Duration(minutes: 15));
      case '1H':
        return startTime.add(const Duration(hours: 1));
      case '1D':
        return startTime.add(const Duration(days: 1));
      case '1W':
        return startTime.add(const Duration(days: 7));
      default:
        return startTime;
    }
  }

  void dispose() {
    for (var controller in _candleControllers.values) {
      controller.close();
    }
  }
}
