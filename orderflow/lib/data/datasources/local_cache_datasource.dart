import 'package:hive/hive.dart';
import '../models/candle_model.dart';
import '../../core/constants/app_constants.dart';
import 'yahoo_datasource.dart';

class LocalCacheDataSource {
  Box<Map>? _candleBox;
  Box<Map>? _orderflowBox;

  /// Initialize Hive and open box
  Future<void> initialize() async {
    _candleBox = await Hive.openBox<Map>(AppConstants.candleCacheBox);
    _orderflowBox = await Hive.openBox<Map>(AppConstants.orderflowCacheBox);
    
    // Cleanup old data on startup
    await cleanupOldData();
  }

  /// Cache candles for an instrument
  Future<void> cacheCandles(String symbol, List<CandleModel> candles) async {
    if (_candleBox == null) await initialize();

    // Keep only the latest candles
    final candlesToCache = candles.length > AppConstants.maxCachedCandles
        ? candles.sublist(candles.length - AppConstants.maxCachedCandles)
        : candles;

    final candlesJson = candlesToCache.map((c) => c.toJson()).toList();
    await _candleBox!.put(symbol, {'candles': candlesJson});
  }

  /// Get cached candles for an instrument
  Future<List<CandleModel>> getCachedCandles(String symbol) async {
    if (_candleBox == null) await initialize();

    final data = _candleBox!.get(symbol);
    if (data == null) return [];

    try {
      final candlesJson = (data['candles'] as List).cast<Map<dynamic, dynamic>>();
      return candlesJson
          .map((json) => CandleModel.fromJson(Map<String, dynamic>.from(json)))
          .toList();
    } catch (e) {
      print('Error reading cached candles: $e');
      return [];
    }
  }

  /// Add a new candle to cache
  Future<void> addCandle(String symbol, CandleModel candle) async {
    final cachedCandles = await getCachedCandles(symbol);
    
    // Check if candle already exists (update) or add new
    final index = cachedCandles.indexWhere((c) => c.candleKey == candle.candleKey);
    if (index != -1) {
      cachedCandles[index] = candle;
    } else {
      cachedCandles.add(candle);
    }

    // Sort by timeStart
    cachedCandles.sort((a, b) => a.timeStart.compareTo(b.timeStart));

    await cacheCandles(symbol, cachedCandles);
  }

  /// Cache orderflow data for an instrument
  Future<void> cacheOrderflow(String symbol, Map<String, dynamic> data) async {
    if (_orderflowBox == null) await initialize();
    await _orderflowBox!.put(symbol, data);
  }

  /// Get cached orderflow for an instrument
  Future<Map<String, dynamic>> getCachedOrderflow(String symbol) async {
    if (_orderflowBox == null) await initialize();
    final data = _orderflowBox!.get(symbol);
    return data != null ? Map<String, dynamic>.from(data) : {};
  }

  /// Cleanup data older than 3 trading days
  Future<void> cleanupOldData() async {
    final cutoff = YahooDataSource.lastNTradingDaysStart(3).millisecondsSinceEpoch;
    
    // 1. Cleanup Candles
    if (_candleBox != null) {
      for (var key in _candleBox!.keys) {
        final data = _candleBox!.get(key);
        if (data != null && data['candles'] is List) {
          final candlesList = (data['candles'] as List).cast<Map>();
          final filteredCandles = candlesList.where((c) {
            final rawTime = c['timeStart'];
            int time = 0;
            if (rawTime is num) {
              time = rawTime.toInt();
            } else if (rawTime is DateTime) {
              time = rawTime.millisecondsSinceEpoch;
            } else if (rawTime is String) {
              time = int.tryParse(rawTime) ?? 0;
            }
            return time >= cutoff;
          }).toList();
          
          if (filteredCandles.length != candlesList.length) {
            await _candleBox!.put(key, {'candles': filteredCandles});
          }
        }
      }
    }

    // 2. Cleanup Orderflow (Note: orderflow is stored per symbol as a Map of timestamp -> data)
    if (_orderflowBox != null) {
      for (var key in _orderflowBox!.keys) {
        final data = _orderflowBox!.get(key);
        if (data != null) {
          final orderflowMap = Map<dynamic, dynamic>.from(data);
          final initialCount = orderflowMap.length;
          
          orderflowMap.removeWhere((timestamp, value) {
            int time = 0;
            if (timestamp is num) {
              time = timestamp.toInt();
            } else if (timestamp is String) {
              time = int.tryParse(timestamp) ?? 0;
            } else if (timestamp is DateTime) {
              time = timestamp.millisecondsSinceEpoch;
            }
            return time < cutoff;
          });

          if (orderflowMap.length != initialCount) {
             await _orderflowBox!.put(key, orderflowMap);
          }
        }
      }
    }
    
    print('LocalCache cleanup completed. Cutoff: ${DateTime.fromMillisecondsSinceEpoch(cutoff)}');
  }

  /// Clear all cache
  Future<void> clearAllCache() async {
    if (_candleBox == null || _orderflowBox == null) await initialize();
    await _candleBox?.clear();
    await _orderflowBox?.clear();
  }

  /// Close Hive boxes
  Future<void> close() async {
    await _candleBox?.close();
    await _orderflowBox?.close();
  }
}
