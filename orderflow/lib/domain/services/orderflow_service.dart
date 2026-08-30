import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../entities/candle.dart';
import '../entities/ghost_order.dart';
import '../../data/datasources/local_cache_datasource.dart';
import '../../data/repositories/candle_repository.dart';
import '../../data/models/candle_model.dart';
import '../../core/constants/nifty_stocks.dart';
import '../../core/constants/app_constants.dart';

/// Service for managing orderflow data (buyer/seller counts)
class OrderflowService {
  final FirebaseFirestore _firestore;
  final LocalCacheDataSource? _localCache;
  final CandleRepository? _candleRepository;
  static const String _collection = 'orderflow';

  OrderflowService({
    FirebaseFirestore? firestore,
    LocalCacheDataSource? localCache,
    CandleRepository? candleRepository,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _localCache = localCache,
        _candleRepository = candleRepository;

  /// Superuser emails - only these users can input orderflow data
  static const List<String> superuserEmails = [
    'jivaspcet@gmail.com',
    'jivaspect@gmail.com',
    'whatsapplivestatus@gmail.com',
  ];

  static bool isSuperuser(String? email) {
    return AppConstants.isMasterAdmin(email);
  }


  /// Save orderflow data for a specific candle
  Future<void> saveOrderflow({
    required String symbol,
    required DateTime candleTime,
    required int buyerCount,
    required int sellerCount,
    bool isInstitutional = false,
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
    String borderColor = "DEFAULT", // "DEFAULT", "GOLD", "MAGENTA", "CYAN"
    int autoFadeMinutes = 0, // 0 = Never
    Map<double, PriceLevelData>? footprint,
    bool adminOnly = false,
  }) async {
    // Align candleTime to 5-minute mark to ensure consistency with Yahoo chart
    final alignedMs = (candleTime.millisecondsSinceEpoch ~/ (5 * 60 * 1000)) * (5 * 60 * 1000);
    final docId = '${symbol}_$alignedMs';
    final now = DateTime.now();
    final expiryTime = autoFadeMinutes > 0 
        ? now.add(Duration(minutes: autoFadeMinutes)).millisecondsSinceEpoch 
        : null;
    
    final data = {
      'symbol': symbol,
      'candleTime': alignedMs,
      'buyerCount': buyerCount,
      'sellerCount': sellerCount,
      'isInstitutional': isInstitutional,
      'isBigSignal': isBigSignal,
      'isMediumSignal': isMediumSignal,
      'isTrap': isTrap,
      'isLiquidation': isLiquidation,
      'bubbleScale': bubbleScale,
      'bubbleOpacity': bubbleOpacity,
      'bubbleGlow': bubbleGlow,
      'showLabel': showLabel,
      'customTag': customTag,
      'pulseSpeed': pulseSpeed,
      'borderColor': borderColor,
      'expiryTime': expiryTime,
      'footprint': footprint?.map((k, v) => MapEntry(k.toString(), {'buyVolume': v.buyVolume, 'sellVolume': v.sellVolume})),
      'broadcastPush': adminOnly ? false : true, // Triggers Cloud Function notification
      'adminOnly': adminOnly,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': 'ADMIN', // This populates injectedBy flag
    };

    await _firestore.collection(_collection).doc(docId).set(data, SetOptions(merge: true));

    // Also cache locally if it's a "heavy" order
    if (_localCache != null && (isInstitutional || isBigSignal || isMediumSignal || isTrap || isLiquidation || buyerCount >= 10000 || sellerCount >= 10000)) {
       final cachedData = await _localCache!.getCachedOrderflow(symbol);
       cachedData[alignedMs.toString()] = {
         ...data,
         'updatedAt': now.millisecondsSinceEpoch, // Convert FieldValue to int for cache
       };
       await _localCache!.cacheOrderflow(symbol, cachedData);
     }

    // Auto-replicate signals on Nifty 50 constituents if they have the exact same pattern (skip if adminOnly)
    if (symbol == 'NIFTY50' && _candleRepository != null && !adminOnly) {
      _replicateNiftySignalInBackground(
        candleTime: candleTime,
        buyerCount: buyerCount,
        sellerCount: sellerCount,
        isInstitutional: isInstitutional,
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
        footprint: footprint,
      );
    }
  }

  Stream<Map<String, Map<String, dynamic>>> getOrderflowStream(String symbol, {String? currentUserEmail}) {
    // FIREBASE-ONLY: Stream orderflow data from Firestore, last 5 days only.
    // No local cache — Firebase is the single source of truth.
    final twoDaysAgo = DateTime.now().subtract(const Duration(hours: 240)).millisecondsSinceEpoch;
    
    return _firestore
        .collection(_collection)
        .where('symbol', isEqualTo: symbol)
        .where('candleTime', isGreaterThanOrEqualTo: twoDaysAgo)
        .snapshots()
        .map((snapshot) {
      final Map<String, Map<String, dynamic>> data = {};

      for (final doc in snapshot.docs) {
        final docData = doc.data();
        
        final adminOnly = docData['adminOnly'] as bool? ?? false;
        if (adminOnly && !AppConstants.isMasterAdmin(currentUserEmail)) {
          continue;
        }

        // Robustly get candleTime from field or doc ID
        int? candleTime;
        if (docData.containsKey('candleTime')) {
          candleTime = _parseTimestamp(docData['candleTime']);
        }
        if (candleTime == null || candleTime == 0) {
          final idPart = doc.id.contains('_') ? doc.id.split('_').last : doc.id;
          candleTime = int.tryParse(idPart);
        }
        if (candleTime == null || candleTime == 0) continue;

        data[candleTime.toString()] = {
          'buyerCount': (docData['buyerCount'] as num?)?.toInt() ?? 0,
          'sellerCount': (docData['sellerCount'] as num?)?.toInt() ?? 0,
          'isInstitutional': docData['isInstitutional'] as bool? ?? false,
          'isBigSignal': docData['isBigSignal'] as bool? ?? false,
          'isMediumSignal': docData['isMediumSignal'] as bool? ?? false,
          'isTrap': docData['isTrap'] as bool? ?? false,
          'isLiquidation': docData['isLiquidation'] as bool? ?? false,
          'bubbleScale': (docData['bubbleScale'] as num?)?.toDouble() ?? 5.0,
          'bubbleOpacity': (docData['bubbleOpacity'] as num?)?.toDouble() ?? 0.65,
          'bubbleGlow': (docData['bubbleGlow'] as num?)?.toDouble() ?? 0.0,
          'showLabel': docData['showLabel'] as bool? ?? true,
          'customTag': docData['customTag'] as String? ?? '',
          'pulseSpeed': (docData['pulseSpeed'] as num?)?.toDouble() ?? 1.0,
          'borderColor': docData['borderColor'] as String? ?? 'DEFAULT',
          'expiryTime': docData['expiryTime'] as int?,
          'updatedAt': _parseTimestamp(docData['updatedAt']),
          'injectedBy': docData['updatedBy'] as String?,
          'footprint': docData['footprint'] as Map<String, dynamic>?,
          'adminOnly': adminOnly,
        };
      }
      return data;
    });
  }

  Stream<List<Map<String, dynamic>>> getGlobalSignalsStream({String? currentUserEmail}) {
    // Return all orderflow signals created today (since midnight local time).
    final now = DateTime.now();
    final startTime = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    return _firestore
        .collection(_collection)
        .where('candleTime', isGreaterThanOrEqualTo: startTime)
        .snapshots()
        .map((snapshot) {
      final List<Map<String, dynamic>> signals = [];
      for (final doc in snapshot.docs) {
        final docData = doc.data();
        
        final adminOnly = docData['adminOnly'] as bool? ?? false;
        if (adminOnly && !AppConstants.isMasterAdmin(currentUserEmail)) {
          continue;
        }

        final expiryTime = docData['expiryTime'] as int?;
        if (expiryTime != null && expiryTime < DateTime.now().millisecondsSinceEpoch) {
          continue;
        }

        final buyerCount = (docData['buyerCount'] as num?)?.toInt() ?? 0;
        final sellerCount = (docData['sellerCount'] as num?)?.toInt() ?? 0;
        
        final parsedCandleTime = _parseTimestamp(docData['candleTime']);
        final parsedUpdatedAt = _parseTimestamp(docData['updatedAt']);

        signals.add({
          'symbol': docData['symbol'] as String? ?? '',
          'candleTime': parsedCandleTime > 0 ? parsedCandleTime : parsedUpdatedAt,
          'buyerCount': buyerCount,
          'sellerCount': sellerCount,
          'isInstitutional': docData['isInstitutional'] as bool? ?? false,
          'isBigSignal': docData['isBigSignal'] as bool? ?? false,
          'isMediumSignal': docData['isMediumSignal'] as bool? ?? false,
          'isTrap': docData['isTrap'] as bool? ?? false,
          'isLiquidation': docData['isLiquidation'] as bool? ?? false,
          'customTag': docData['customTag'] as String? ?? '',
          'adminOnly': adminOnly,
        });
      }
      // Sort by candleTime descending (most recent first)
      signals.sort((a, b) => (b['candleTime'] as int).compareTo(a['candleTime'] as int));
      return signals;
    });
  }

  static int _parseTimestamp(dynamic value) {
    if (value == null) return 0;
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is int) {
      if (value < 10000000000 && value > 0) return value * 1000;
      return value;
    }
    if (value is double) {
      final val = value.toInt();
      if (val < 10000000000 && val > 0) return val * 1000;
      return val;
    }
    if (value is String) {
      String part = value;
      if (part.contains('_')) {
        part = part.split('_').last;
      }
      final parsedInt = int.tryParse(part);
      if (parsedInt != null && parsedInt > 0) {
        if (parsedInt < 10000000000) return parsedInt * 1000;
        return parsedInt;
      }
      final dt = DateTime.tryParse(value);
      return dt?.millisecondsSinceEpoch ?? 0;
    }
    return 0;
  }

  Future<Map<String, Map<String, dynamic>>> getOrderflowData(String symbol, {int? startTime, String? currentUserEmail}) async {
    try {
      // FIREBASE-ONLY: Always fetch from Firestore, last 5 days max.
      // startTime is clamped to enforce the 10-day retention limit.
      final twoDaysAgo = DateTime.now().subtract(const Duration(hours: 240)).millisecondsSinceEpoch;
      final finalStartTime = startTime != null
          ? startTime.clamp(twoDaysAgo, double.maxFinite.toInt())
          : twoDaysAgo;

      final snapshot = await _firestore
          .collection(_collection)
          .where('symbol', isEqualTo: symbol)
          .where('candleTime', isGreaterThanOrEqualTo: finalStartTime)
          .get();

      final Map<String, Map<String, dynamic>> allData = {};
      
      for (final doc in snapshot.docs) {
        final docData = doc.data();
        
        final adminOnly = docData['adminOnly'] as bool? ?? false;
        if (adminOnly && !AppConstants.isMasterAdmin(currentUserEmail)) {
          continue;
        }

        int candleTime = _parseTimestamp(docData['candleTime']);
        
        if (candleTime == 0) {
          final idPart = doc.id.contains('_') ? doc.id.split('_').last : doc.id;
          candleTime = int.tryParse(idPart) ?? 0;
        }
        if (candleTime == 0) continue;
        
        allData[candleTime.toString()] = {
          'buyerCount': (docData['buyerCount'] as num?)?.toInt() ?? 0,
          'sellerCount': (docData['sellerCount'] as num?)?.toInt() ?? 0,
          'isInstitutional': docData['isInstitutional'] as bool? ?? false,
          'isBigSignal': docData['isBigSignal'] as bool? ?? false,
          'isMediumSignal': docData['isMediumSignal'] as bool? ?? false,
          'isTrap': docData['isTrap'] as bool? ?? false,
          'isLiquidation': docData['isLiquidation'] as bool? ?? false,
          'bubbleScale': (docData['bubbleScale'] as num?)?.toDouble() ?? 5.0,
          'bubbleOpacity': (docData['bubbleOpacity'] as num?)?.toDouble() ?? 0.65,
          'bubbleGlow': (docData['bubbleGlow'] as num?)?.toDouble() ?? 0.0,
          'showLabel': docData['showLabel'] as bool? ?? true,
          'customTag': docData['customTag'] as String? ?? '',
          'pulseSpeed': (docData['pulseSpeed'] as num?)?.toDouble() ?? 1.0,
          'borderColor': docData['borderColor'] as String? ?? 'DEFAULT',
          'expiryTime': docData['expiryTime'] as int?,
          'injectedBy': docData['updatedBy'] as String?,
          'footprint': docData['footprint'] as Map<String, dynamic>?,
          'adminOnly': adminOnly,
        };
      }
      return allData;
    } catch (e) {
      print('OrderflowService: Error getting orderflow data for $symbol: $e');
      return {};
    }
  }

  /// RESTING/GHOST ORDERS Support
  Future<void> saveGhostOrder(GhostOrder ghost) async {
    await _firestore.collection('ghost_orders').doc(ghost.id).set(ghost.toJson());
  }

  Stream<List<GhostOrder>> getGhostOrdersStream(String triggerSymbol, {String? currentUserEmail}) {
     return _firestore
         .collection('ghost_orders')
         .where('triggerSymbol', isEqualTo: triggerSymbol)
         .where('isTriggered', isEqualTo: false)
         .snapshots()
         .map((snapshot) {
       final List<GhostOrder> list = [];
       for (final doc in snapshot.docs) {
         final ghost = GhostOrder.fromJson(doc.data());
         if (ghost.adminOnly && !AppConstants.isMasterAdmin(currentUserEmail)) {
           continue;
         }
         list.add(ghost);
       }
       return list;
     });
   }

  Future<void> realizeGhostOrder(GhostOrder ghost, DateTime candleTime) async {
    await _firestore.collection('ghost_orders').doc(ghost.id).update({'isTriggered': true});
    await saveOrderflow(
      symbol: ghost.symbol,
      candleTime: candleTime,
      buyerCount: ghost.buyerCount,
      sellerCount: ghost.sellerCount,
      isInstitutional: ghost.isInstitutional,
      isBigSignal: ghost.isBigSignal,
      isMediumSignal: ghost.isMediumSignal,
      isTrap: ghost.isTrap,
      isLiquidation: ghost.isLiquidation,
      bubbleScale: ghost.bubbleScale,
      customTag: "GHOST TRIGGER",
      adminOnly: ghost.adminOnly,
    );
  }

  Future<void> wipeOrderflowForDay(String symbol) async {
    final querySnapshot = await _firestore
        .collection(_collection)
        .where('symbol', isEqualTo: symbol)
        .get();

    final batch = _firestore.batch();
    for (final doc in querySnapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    
    // Also clear local cache for this symbol
    if (_localCache != null) {
       await _localCache!.cacheOrderflow(symbol, {});
    }
  }

  /// Revoke (delete) orderflow for a specific candle
  Future<void> revokeOrderflow({
    required String symbol,
    required DateTime candleTime,
  }) async {
    final docId = '${symbol}_${candleTime.millisecondsSinceEpoch}';
    
    // Delete from Firestore
    await _firestore.collection(_collection).doc(docId).delete();

    // Remove from local cache
    if (_localCache != null) {
      final cachedData = await _localCache!.getCachedOrderflow(symbol);
      final key = candleTime.millisecondsSinceEpoch.toString();
      if (cachedData.containsKey(key)) {
        cachedData.remove(key);
        await _localCache!.cacheOrderflow(symbol, cachedData);
      }
    }
  }

  Future<Map<String, Map<String, dynamic>>> getOrderflowForDate(String symbol, DateTime date, {String? currentUserEmail}) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day, 0, 0, 0).millisecondsSinceEpoch;
      final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59).millisecondsSinceEpoch;
      
      final snapshot = await _firestore
          .collection(_collection)
          .where('symbol', isEqualTo: symbol)
          .where('candleTime', isGreaterThanOrEqualTo: startOfDay)
          .where('candleTime', isLessThanOrEqualTo: endOfDay)
          .get();
          
      final Map<String, Map<String, dynamic>> allData = {};
      for (final doc in snapshot.docs) {
        final docData = doc.data();
        
        final adminOnly = docData['adminOnly'] as bool? ?? false;
        if (adminOnly && !AppConstants.isMasterAdmin(currentUserEmail)) {
          continue;
        }

        int candleTime = _parseTimestamp(docData['candleTime']);
        if (candleTime == 0) continue;
        
        allData[candleTime.toString()] = {
          'buyerCount': (docData['buyerCount'] as num?)?.toInt() ?? 0,
          'sellerCount': (docData['sellerCount'] as num?)?.toInt() ?? 0,
          'isInstitutional': docData['isInstitutional'] as bool? ?? false,
          'isBigSignal': docData['isBigSignal'] as bool? ?? false,
          'isMediumSignal': docData['isMediumSignal'] as bool? ?? false,
          'isTrap': docData['isTrap'] as bool? ?? false,
          'isLiquidation': docData['isLiquidation'] as bool? ?? false,
          'bubbleScale': (docData['bubbleScale'] as num?)?.toDouble() ?? 5.0,
          'bubbleOpacity': (docData['bubbleOpacity'] as num?)?.toDouble() ?? 0.65,
          'bubbleGlow': (docData['bubbleGlow'] as num?)?.toDouble() ?? 0.0,
          'showLabel': docData['showLabel'] as bool? ?? true,
          'customTag': docData['customTag'] as String? ?? '',
          'pulseSpeed': (docData['pulseSpeed'] as num?)?.toDouble() ?? 1.0,
          'borderColor': docData['borderColor'] as String? ?? 'DEFAULT',
          'expiryTime': docData['expiryTime'] as int?,
          'injectedBy': docData['updatedBy'] as String?,
          'footprint': docData['footprint'] as Map<String, dynamic>?,
          'adminOnly': adminOnly,
        };
      }
      return allData;
    } catch (e) {
      print('OrderflowService getOrderflowForDate Error: $e');
      return {};
    }
  }

  void _replicateNiftySignalInBackground({
    required DateTime candleTime,
    required int buyerCount,
    required int sellerCount,
    bool isInstitutional = false,
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
    Map<double, PriceLevelData>? footprint,
  }) {
    Future.microtask(() async {
      print('--- NIFTY50 AUTO-REPLICATION: STARTING SCAN ---');
      try {
        final niftyCandles = await _candleRepository!.fetchHistoricalCandles('NIFTY50');
        CandleModel? niftyCandle;
        for (var c in niftyCandles) {
          if (c.timeStart.millisecondsSinceEpoch == candleTime.millisecondsSinceEpoch) {
            niftyCandle = c;
            break;
          }
        }

        if (niftyCandle == null) {
          print('NIFTY50 AUTO-REPLICATION: Nifty50 candle not found at $candleTime');
          return;
        }

        final niftyPattern = _detectCandlePattern(
          niftyCandle.open,
          niftyCandle.high,
          niftyCandle.low,
          niftyCandle.close,
        );
        print('NIFTY50 AUTO-REPLICATION: Nifty50 pattern is $niftyPattern');

        final scanStocks = NiftyStocks.stocks.keys.toList();
        int matchCount = 0;

        for (final stock in scanStocks) {
          try {
            final stockCandles = await _candleRepository!.fetchHistoricalCandles(stock);
            CandleModel? stockCandle;
            for (var c in stockCandles) {
              if (c.timeStart.millisecondsSinceEpoch == candleTime.millisecondsSinceEpoch) {
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
                print('NIFTY50 AUTO-REPLICATION: Match found on $stock ($stockPattern). Saving replicated signal.');
                matchCount++;
                
                final int stockBuyer = _randomizeVolumeForSymbol(buyerCount, stock);
                final int stockSeller = _randomizeVolumeForSymbol(sellerCount, stock);

                await saveOrderflow(
                  symbol: stock,
                  candleTime: candleTime,
                  buyerCount: stockBuyer,
                  sellerCount: stockSeller,
                  isInstitutional: isInstitutional,
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
                  footprint: footprint,
                );
              }
            }
          } catch (e) {
            print('NIFTY50 AUTO-REPLICATION: Error scanning stock $stock: $e');
          }
          await Future.delayed(const Duration(milliseconds: 50));
        }
        print('--- NIFTY50 AUTO-REPLICATION: COMPLETED (found $matchCount matches) ---');
      } catch (e, s) {
        print('NIFTY50 AUTO-REPLICATION: General error: $e\n$s');
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
