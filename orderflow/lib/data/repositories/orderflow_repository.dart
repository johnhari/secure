import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../datasources/remote_datasource.dart';
import '../datasources/local_cache_datasource.dart';
import 'candle_repository.dart';
import '../models/candle_model.dart';
import '../../core/constants/nifty_stocks.dart';

class OrderflowRepository {
  final RemoteDataSource _remoteDataSource;
  final LocalCacheDataSource _localCache;
  final CandleRepository? _candleRepository;

  OrderflowRepository({
    required RemoteDataSource remoteDataSource,
    required LocalCacheDataSource localCache,
    CandleRepository? candleRepository,
  })  : _remoteDataSource = remoteDataSource,
        _localCache = localCache,
        _candleRepository = candleRepository;

  /// Robustly extracts epoch milliseconds from candleKey strings (handles symbol prefixes and seconds/ms)
  static int parseCandleKeyToTimestampMs(String key) {
    if (key.isEmpty) return 0;
    String part = key;
    if (part.contains('_')) {
      part = part.split('_').last;
    }
    int val = int.tryParse(part) ?? 0;
    if (val == 0) return 0;
    // Convert 10-digit epoch seconds to epoch milliseconds
    if (val < 10000000000 && val > 0) {
      val *= 1000;
    }
    return val;
  }

  /// Save orderflow data for multiple candles at once
  Future<void> saveOrderflowBulk({
    required List<String> candleKeys,
    required String symbol,
    required int buyerCount,
    required int sellerCount,
    required String adminUid,
    bool isBigSignal = false,
    bool isMediumSignal = false,
    bool isTrap = false,
    bool isLiquidation = false,
    double bubbleScale = 5.0,
    double bubbleOpacity = 0.65,
    double bubbleGlow = 0.0,
    bool showLabel = true,
    String customTag = "",
    double pulseSpeed = 1.0,
    String borderColor = "DEFAULT",
    int autoFadeMinutes = 0,
    bool broadcastPush = false,
    bool adminOnly = false,
  }) async {
    final firestore = _remoteDataSource.firestore;
    final batch = firestore.batch();
    final now = DateTime.now();
    
    final Map<String, dynamic> cachedData = await _localCache.getCachedOrderflow(symbol);

    for (int i = 0; i < candleKeys.length; i++) {
      final key = candleKeys[i];
      final intTime = parseCandleKeyToTimestampMs(key);
      
      // Align to 5-minute mark to ensure consistency with Yahoo chart
      final alignedTimeMs = intTime > 0 
          ? (intTime ~/ (5 * 60 * 1000)) * (5 * 60 * 1000)
          : now.millisecondsSinceEpoch;
      final alignedKey = alignedTimeMs.toString();
      final docId = '${symbol}_$alignedKey';
      final expiryTime = autoFadeMinutes > 0 
          ? now.add(Duration(minutes: autoFadeMinutes)).millisecondsSinceEpoch 
          : null;

      // Only broadcast push for the LAST document in the batch to avoid triple notifications (skip if adminOnly)
      final shouldBroadcast = !adminOnly && broadcastPush && (i == candleKeys.length - 1);

      final data = {
        'candleKey': alignedKey,
        'candleTime': alignedTimeMs,
        'symbol': symbol,
        'buyerCount': buyerCount,
        'sellerCount': sellerCount,
        'bubbleScale': bubbleScale,
        'bubbleOpacity': bubbleOpacity,
        'bubbleGlow': bubbleGlow,
        'showLabel': showLabel,
        'isBigSignal': isBigSignal,
        'isMediumSignal': isMediumSignal,
        'isTrap': isTrap,
        'isLiquidation': isLiquidation,
        'customTag': customTag,
        'pulseSpeed': pulseSpeed,
        'borderColor': borderColor,
        'expiryTime': expiryTime,
        'broadcastPush': shouldBroadcast, // Triggers Cloud Function
        'adminOnly': adminOnly,
        'isInstitutional': false,
        'updatedBy': adminUid,
        'injectedBy': adminUid,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      batch.set(firestore.collection('orderflow').doc(docId), data, SetOptions(merge: true));

      // Cache locally if it's a "heavy" order
      if (isBigSignal || isMediumSignal || isTrap || isLiquidation || buyerCount >= 10000 || sellerCount >= 10000) {
         cachedData[alignedKey] = {
           ...data,
           'updatedAt': now.millisecondsSinceEpoch,
         };
      }
    }
    
    await batch.commit();
    
    // Save updated cache
    if (cachedData.isNotEmpty) {
       await _localCache.cacheOrderflow(symbol, cachedData);
    }

    // Auto-replicate signals on Nifty 50 constituents if they have the exact same pattern
    if (symbol == 'NIFTY50' && _candleRepository != null) {
      _replicateNiftySignalBulkInBackground(
        candleKeys: candleKeys,
        buyerCount: buyerCount,
        sellerCount: sellerCount,
        adminUid: adminUid,
        isBigSignal: isBigSignal,
        isMediumSignal: isMediumSignal,
        isTrap: isTrap,
        isLiquidation: isLiquidation,
        bubbleScale: bubbleScale,
        bubbleOpacity: bubbleOpacity,
        bubbleGlow: bubbleGlow,
        showLabel: showLabel,
        customTag: customTag,
        pulseSpeed: pulseSpeed,
        borderColor: borderColor,
        autoFadeMinutes: autoFadeMinutes,
      );
    }
  }

  /// Delete a specific orderflow document
  Future<void> deleteOrderflowDirect({
    required String candleKey,
    required String symbol,
  }) async {
    final firestore = _remoteDataSource.firestore;
    final docId = '${symbol}_$candleKey';
    await firestore.collection('orderflow').doc(docId).delete();
    
    // Also remove from local cache
    final cachedData = await _localCache.getCachedOrderflow(symbol);
    if (cachedData.containsKey(candleKey)) {
       cachedData.remove(candleKey);
       await _localCache.cacheOrderflow(symbol, cachedData);
    }
  }

  /// Wipe all orderflow data for a symbol
  Future<void> wipeOrderflowForDay({
    required String symbol,
  }) async {
    final firestore = _remoteDataSource.firestore;
    final query = await firestore
        .collection('orderflow')
        .where('symbol', isEqualTo: symbol)
        .get();

    final batch = firestore.batch();
    for (var doc in query.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    
    // Clear local cache for this symbol
    await _localCache.cacheOrderflow(symbol, {});
  }

  /// Get orderflow for a candle
  Future<Map<String, dynamic>?> getOrderflow({
    required String token,
    required String candleKey,
  }) async {
    return await _remoteDataSource.getOrderflow(
      token: token,
      candleKey: candleKey,
    );
  }

  /// Get all orderflow for symbol and date
  Future<List<Map<String, dynamic>>> getOrderflowBySymbolAndDate({
    required String token,
    required String symbol,
    required DateTime date,
  }) async {
    return await _remoteDataSource.getOrderflowBySymbolAndDate(
      token: token,
      symbol: symbol,
      date: date,
    );
  }

  void _replicateNiftySignalBulkInBackground({
    required List<String> candleKeys,
    required int buyerCount,
    required int sellerCount,
    required String adminUid,
    bool isBigSignal = false,
    bool isMediumSignal = false,
    bool isTrap = false,
    bool isLiquidation = false,
    double bubbleScale = 5.0,
    double bubbleOpacity = 0.65,
    double bubbleGlow = 0.0,
    bool showLabel = true,
    String customTag = "",
    double pulseSpeed = 1.0,
    String borderColor = "DEFAULT",
    int autoFadeMinutes = 0,
  }) {
    Future.microtask(() async {
      print('--- NIFTY50 BULK AUTO-REPLICATION: STARTING SCAN ---');
      try {
        final niftyCandles = await _candleRepository!.fetchHistoricalCandles('NIFTY50');
        
        for (final key in candleKeys) {
          final intTime = parseCandleKeyToTimestampMs(key);
          if (intTime == 0) continue;

          CandleModel? niftyCandle;
          for (var c in niftyCandles) {
            final cMs = c.timeStart.millisecondsSinceEpoch;
            final cBucket = cMs ~/ (5 * 60 * 1000);
            final keyBucket = intTime ~/ (5 * 60 * 1000);
            if (cMs == intTime || cBucket == keyBucket) {
              niftyCandle = c;
              break;
            }
          }

          if (niftyCandle == null) {
            print('NIFTY50 BULK AUTO-REPLICATION: Nifty50 candle not found at $intTime');
            continue;
          }

          final niftyPattern = _detectCandlePattern(
            niftyCandle.open,
            niftyCandle.high,
            niftyCandle.low,
            niftyCandle.close,
          );
          print('NIFTY50 BULK AUTO-REPLICATION: Nifty50 pattern is $niftyPattern');

          final scanStocks = NiftyStocks.stocks.keys.toList();
          int matchCount = 0;

          for (final stock in scanStocks) {
            try {
              final stockCandles = await _candleRepository!.fetchHistoricalCandles(stock);
              CandleModel? stockCandle;
              for (var c in stockCandles) {
                if (c.timeStart.millisecondsSinceEpoch == intTime) {
                  stockCandle = c;
                  break;
                }
              }

              if (stockCandle != null) {
                final stockPattern = _detectCandlePattern(
                  stockCandle.open,
                  stockCandle.high,
                  stockCandle.low,
                  stockCandle.close,
                );
                if (stockPattern == niftyPattern) {
                  print('NIFTY50 BULK AUTO-REPLICATION: Match found on $stock ($stockPattern). Saving replicated bulk signal.');
                  matchCount++;

                  final int stockBuyer = _randomizeVolumeForSymbol(buyerCount, stock);
                  final int stockSeller = _randomizeVolumeForSymbol(sellerCount, stock);

                  await saveOrderflowBulk(
                    candleKeys: [key],
                    symbol: stock,
                    buyerCount: stockBuyer,
                    sellerCount: stockSeller,
                    adminUid: adminUid,
                    isBigSignal: isBigSignal,
                    isMediumSignal: isMediumSignal,
                    isTrap: isTrap,
                    isLiquidation: isLiquidation,
                    bubbleScale: bubbleScale,
                    bubbleOpacity: bubbleOpacity,
                    bubbleGlow: bubbleGlow,
                    showLabel: showLabel,
                    customTag: customTag.isEmpty ? "REPLICATED" : customTag,
                    pulseSpeed: pulseSpeed,
                    borderColor: borderColor,
                    autoFadeMinutes: autoFadeMinutes,
                    broadcastPush: false, // Don't spam push notifications
                  );
                }
              }
            } catch (e) {
              print('NIFTY50 BULK AUTO-REPLICATION: Error scanning stock $stock: $e');
            }
            await Future.delayed(const Duration(milliseconds: 50));
          }
          print('--- NIFTY50 BULK AUTO-REPLICATION: COMPLETED FOR KEY $key (found $matchCount matches) ---');
        }
      } catch (e, s) {
        print('NIFTY50 BULK AUTO-REPLICATION: General error: $e\n$s');
      }
    });
  }

  String _detectCandlePattern(double open, double high, double low, double close) {
    final range = high - low;
    if (range <= 0) return 'DOJI';

    final body = (close - open).abs();
    final upperWick = high - (close > open ? close : open);
    final lowerWick = (close > open ? open : close) - low;

    final bodyRatio = body / range;
    final isBullish = close >= open;

    if (bodyRatio <= 0.1) {
      return 'DOJI';
    } else if (bodyRatio >= 0.85) {
      return isBullish ? 'BULLISH_MARUBOZU' : 'BEARISH_MARUBOZU';
    } else if (lowerWick >= body * 2 && upperWick <= range * 0.15) {
      return isBullish ? 'BULLISH_HAMMER' : 'BEARISH_HAMMER';
    } else if (upperWick >= body * 2 && lowerWick <= range * 0.15) {
      return isBullish ? 'BULLISH_INVERTED_HAMMER' : 'BEARISH_SHOOTING_STAR';
    } else if (bodyRatio <= 0.4 && upperWick >= range * 0.2 && lowerWick >= range * 0.2) {
      return isBullish ? 'BULLISH_SPINNING_TOP' : 'BEARISH_SPINNING_TOP';
    } else {
      return isBullish ? 'NORMAL_BULLISH' : 'NORMAL_BEARISH';
    }
  }

  int _randomizeVolumeForSymbol(int base, String symbol) {
    if (base <= 0) return 0;
    final random = math.Random();
    
    // Check if symbol is an index
    final bool isIndex = NiftyStocks.indices.containsKey(symbol.toUpperCase());
    
    // Scale factor: indices 60% to 140%, stocks 20% to 120%
    final double scale = isIndex 
        ? (0.6 + random.nextDouble() * 0.8) 
        : (0.2 + random.nextDouble() * 1.0);
        
    int scaledBase = (base * scale).round();
    if (scaledBase <= 0) scaledBase = 10;
    
    // Apply 15% random variance
    final variance = (scaledBase * 0.15).toInt();
    if (variance == 0) return scaledBase;
    
    final change = random.nextInt(variance * 2 + 1) - variance;
    int result = scaledBase + change;
    
    // Avoid multiples of 10 for organic look
    if (result % 10 == 0) {
      result += random.nextInt(9) + 1;
    }
    return result;
  }
}
