import 'dart:math' as math;
import '../datasources/yahoo_datasource.dart';
import '../datasources/websocket_datasource.dart';
import '../datasources/local_cache_datasource.dart';
import '../datasources/firebase_market_datasource.dart';
import '../models/candle_model.dart';
import '../../core/constants/app_constants.dart';

class CandleRepository {
  final WebSocketDataSource _webSocketDataSource;
  final YahooDataSource _yahooDataSource;
  final FirebaseMarketDataSource _firebaseMarketDataSource;
  final LocalCacheDataSource _localCache;

  CandleRepository({
    required WebSocketDataSource webSocketDataSource,
    required YahooDataSource yahooDataSource,
    required FirebaseMarketDataSource firebaseMarketDataSource,
    required LocalCacheDataSource localCache,
  })  : _webSocketDataSource = webSocketDataSource,
        _yahooDataSource = yahooDataSource,
        _firebaseMarketDataSource = firebaseMarketDataSource,
        _localCache = localCache;

  /// Fetch candles with local cache support (2-day policy)
  Future<List<CandleModel>> fetchHistoricalCandles(String symbol) async {
    try {
      // 1. Get cached candles
      final cached = await _localCache.getCachedCandles(symbol);
      print('CandleRepository [$symbol]: Loaded ${cached.length} candles from local cache');
      
      // 2. Fetch fresh data from Yahoo and Firebase in parallel with tighter timeouts
      List<CandleModel> yahooFetched = [];
      List<CandleModel> firebaseFetched = [];

      try {
        print('CandleRepository [$symbol]: Starting parallel fetch (Yahoo + Firebase)...');
        
        final results = await Future.wait([
          _yahooDataSource.fetchHistoricalCandles(symbol)
              .timeout(const Duration(seconds: 10), onTimeout: () {
                print('CandleRepository [$symbol]: Yahoo fetch timed out (10s)');
                return [];
              }),
          _firebaseMarketDataSource.fetchHistoricalCandles(symbol)
              .timeout(const Duration(seconds: 10), onTimeout: () {
                print('CandleRepository [$symbol]: Firebase fetch timed out (10s)');
                return [];
              }),
        ]);

        yahooFetched = results[0];
        firebaseFetched = results[1];
        
        print('CandleRepository [$symbol]: Fetch complete. Yahoo: ${yahooFetched.length}, Firebase: ${firebaseFetched.length}');
      } catch (e) {
        print('CandleRepository [$symbol]: Parallel fetch error: $e');
      }
      
      // Merge results: Start with cached, then add Yahoo, then add Firebase (latest takes precedence)
      final Map<String, CandleModel> candleMap = {
        for (var c in cached) c.candleKey: c,
      };
      
      // Merge Yahoo data
      for (var c in yahooFetched) {
        candleMap[c.candleKey] = _mergeCandle(candleMap[c.candleKey], c);
      }
      
      // Merge Firebase data
      for (var c in firebaseFetched) {
        candleMap[c.candleKey] = _mergeCandle(candleMap[c.candleKey], c);
      }

      // Secondary dedup: collapse candles with different candleKeys but the same
      // 5-minute time bucket (e.g. Yahoo ms-key vs. bootstrap ms-key edge cases).
      final Map<int, CandleModel> bucketMap = {};
      for (final c in candleMap.values) {
        final bucket = (c.timeStart.millisecondsSinceEpoch ~/ (5 * 60 * 1000));
        final existing = bucketMap[bucket];
        if (existing == null) {
          bucketMap[bucket] = c;
        } else {
          // Prefer the candle with more data (non-zero buyerCount / injected)
          final prefer = (c.buyerCount != null && c.buyerCount! > 0) ? c : existing;
          bucketMap[bucket] = _mergeCandle(existing, prefer);
        }
      }

      final merged = bucketMap.values.toList()
        ..sort((a, b) => a.timeStart.compareTo(b.timeStart));

      // Filter to only the last 3 trading days of data
      final cutoff = YahooDataSource.lastNTradingDaysStart(3);
      final filteredMerged = merged.where((c) => !c.timeStart.isBefore(cutoff)).toList();

      // Limit to max cached candles (e.g. 600)
      final List<CandleModel> finalCandles = filteredMerged.length > AppConstants.maxCachedCandles
          ? filteredMerged.sublist(filteredMerged.length - AppConstants.maxCachedCandles)
          : filteredMerged;

      if (finalCandles.isEmpty) {
        print('CandleRepository [$symbol]: No candles found, bootstrapping from zero');
        return _ensureLiveNode(symbol, []);
      }

      final result = _ensureLiveNode(symbol, finalCandles);
      
      // Filter result one final time just in case _ensureLiveNode added older nodes
      final filteredResult = result.where((c) => !c.timeStart.isBefore(cutoff)).toList();

      // Save back to cache to ensure 'last 3 days' are persisted even if Yahoo is throttled next time
      await _localCache.cacheCandles(symbol, filteredResult);
      
      return filteredResult;
    } catch (e) {
      print('CandleRepository [$symbol]: Error in fetchHistoricalCandles: $e');
      final cached = await getCachedCandles(symbol);
      final cutoff = YahooDataSource.lastNTradingDaysStart(3);
      final result = _ensureLiveNode(symbol, cached);
      return result.where((c) => !c.timeStart.isBefore(cutoff)).toList();
    }
  }

  /// Ensures that during market hours (or for the current trading day), there are nodes for all intervals.
  /// This allows admins to always have nodes to select for injection even if Yahoo is throttled.
  List<CandleModel> _ensureLiveNode(String symbol, List<CandleModel> currentCandles) {
    final now = DateTime.now();
    final istNow = now.toUtc().add(const Duration(hours: 5, minutes: 30));
    
    final marketStartTodayLocal = DateTime.utc(istNow.year, istNow.month, istNow.day, 3, 45).toLocal();
    final marketEndTodayLocal = DateTime.utc(istNow.year, istNow.month, istNow.day, 10, 10).toLocal();
    
    // Filter out invalid zero/corrupt candles
    final validCurrentCandles = currentCandles.where((c) =>
      c.open > 0 && c.high > 0 && c.low > 0 && c.close > 0 && c.timeStart.year >= 2000
    ).toList();

    // --- AGGRESSIVE MULTI-DAY BOOTSTRAP ---
    // If empty or sparse, generate/fill last 3 trading days to ensure a rich terminal history
    if (validCurrentCandles.length < 50) { 
      print('CandleRepository [$symbol]: History sparse (${validCurrentCandles.length} nodes). Ensuring 3-day bootstrap for Web stability...');
      List<CandleModel> bootstrapNodes = [];
      double lastClose = (symbol.toUpperCase().contains('BANK')) ? 52200.0 : 24232.0;
      if (validCurrentCandles.isNotEmpty) {
        lastClose = validCurrentCandles.last.close;
      }
      
      for (int d = 2; d >= 0; d--) {
        final targetDate = istNow.subtract(Duration(days: d));
        final bool isTargetTradingDay = targetDate.weekday <= 5;
        if (!isTargetTradingDay) continue; 

        final sessionStart = DateTime.utc(targetDate.year, targetDate.month, targetDate.day, 3, 45).toLocal();
        final sessionEnd = DateTime.utc(targetDate.year, targetDate.month, targetDate.day, 10, 10).toLocal();

        DateTime generationLimit = sessionEnd;
        if (d == 0) {
          if (now.isBefore(sessionStart)) continue;
          generationLimit = now.isBefore(sessionEnd) ? now : sessionEnd;
        }

        DateTime iterator = sessionStart;
        while (iterator.isBefore(generationLimit)) {
          final random = math.Random(iterator.millisecondsSinceEpoch);
          final double maxBarMove = (symbol.toUpperCase().contains('BANK')) ? 14.0 : 5.5;
          final double change = (random.nextDouble() - 0.5) * maxBarMove;
          final double open = lastClose;
          final double close = open + change;
          final double maxWick = (symbol.toUpperCase().contains('BANK')) ? 6.0 : 2.5;
          final double wick = random.nextDouble() * maxWick;
          final double high = math.max(open, close) + wick;
          final double low = math.min(open, close) - wick;

          bootstrapNodes.add(CandleModel(
            symbol: symbol,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: 1000 + random.nextInt(5000),
            timeStart: iterator,
            timeEnd: iterator.add(const Duration(minutes: 5)),
            candleKey: iterator.millisecondsSinceEpoch.toString(),
            isClosed: true,
          ));
          
          lastClose = close;
          iterator = iterator.add(const Duration(minutes: 5));
        }
      }
      
      if (bootstrapNodes.isNotEmpty) {
        final Map<int, CandleModel> map = {};
        for (var c in bootstrapNodes) {
          map[c.timeStart.millisecondsSinceEpoch ~/ (5 * 60 * 1000)] = c;
        }
        for (var c in validCurrentCandles) {
          map[c.timeStart.millisecondsSinceEpoch ~/ (5 * 60 * 1000)] = c;
        }
        final mergedBootstrap = map.values.toList()..sort((a, b) => a.timeStart.compareTo(b.timeStart));
        print('CandleRepository [$symbol]: CRITICAL BOOTSTRAP - Generated ${mergedBootstrap.length} historical nodes.');
        return mergedBootstrap;
      }
    }

    // Standard today-sync if we have data
    final bool isTradingDay = YahooDataSource.isTradingDay(istNow);
    DateTime generationEnd;
    
    if (!isTradingDay) {
      // Do NOT generate virtual candles on weekends/holidays. Leave the chart empty for today.
      generationEnd = marketStartTodayLocal;
    } else if (now.isAfter(marketEndTodayLocal)) {
      // Market has closed for today — generate nodes up to 3:40 PM IST
      generationEnd = marketEndTodayLocal;
    } else if (now.isBefore(marketStartTodayLocal)) {
      // Pre-market on a trading day — generate up to yesterday's close basically (or just return existing)
      generationEnd = marketStartTodayLocal;
    } else {
      // Market is open — generate nodes up to the current 5-minute interval
      generationEnd = DateTime.fromMillisecondsSinceEpoch(
        (now.millisecondsSinceEpoch ~/ (5 * 60 * 1000)) * (5 * 60 * 1000),
        isUtc: now.isUtc,
      );
    }

    final List<CandleModel> list = List.from(currentCandles);
    // Sort initially to make searching faster and lastPrice reliable
    list.sort((a, b) => a.timeStart.compareTo(b.timeStart));
    
    // Create a Set of existing timestamps for O(1) lookup
    final existingTimes = list.map((c) => c.timeStart.millisecondsSinceEpoch).toSet();

    DateTime iterator = marketStartTodayLocal;
    bool addedAny = false;
    
    // Find initial lastPrice from existing data before the iterator
    double currentLastPrice = 0.0;
    try {
      final lastKnown = list.lastWhere(
        (c) => c.timeStart.isBefore(iterator) || c.timeStart.isAtSameMomentAs(iterator),
      );
      currentLastPrice = lastKnown.close;
    } catch (_) {
      // If no node before 9:15, use the very first node's open price as a fallback
      if (list.isNotEmpty) {
        currentLastPrice = list.first.open;
      }
    }

    // FINAL FALLBACK: If still 0 and list is not empty, use the very last candle's close
    if (currentLastPrice == 0.0 && list.isNotEmpty) {
      currentLastPrice = list.last.close;
    }

    // ── HARD SEED FALLBACK ────────────────────────────────────────────────────
    // If we have no reference price, use a hardcoded safe seed for the instrument
    // This ensures the chart AT LEAST boots up and allows injection even if Yahoo is down.
    if (currentLastPrice == 0.0) {
      final Map<String, double> hardSeeds = {
        '^NSEI': 24200.0,
        '^NSEBANK': 52500.0,
        'NIFTY': 24200.0,
        'BANKNIFTY': 52500.0,
      };
      currentLastPrice = hardSeeds[symbol.toUpperCase()] ?? 24000.0;
      print('CandleRepository [$symbol]: Using hardcoded seed price: $currentLastPrice');
    }

    while (iterator.isBefore(generationEnd)) {
      final int ts = iterator.millisecondsSinceEpoch;
      
      if (!existingTimes.contains(ts)) {
        final int step = list.length;
        final double direction = (step % 2 == 0) ? 1.0 : -1.0;
        final double bodySize = 8.0 + (step % 5) * 3.0;
        final double wickSize = 4.0 + (step % 3) * 2.0;
        
        final double openPrice = currentLastPrice;
        final double closePrice = openPrice + (direction * bodySize);
        final double highPrice = math.max(openPrice, closePrice) + wickSize;
        final double lowPrice = math.min(openPrice, closePrice) - wickSize;

        list.add(CandleModel(
          symbol: symbol,
          timeStart: iterator,
          timeEnd: iterator.add(const Duration(minutes: 5)),
          open: openPrice,
          high: highPrice,
          low: lowPrice,
          close: closePrice,
          volume: 120 + (step % 7) * 45,
          candleKey: ts.toString(),
        ));
        
        currentLastPrice = closePrice;
        addedAny = true;
      } else {
        final existing = list.firstWhere((c) => c.timeStart.millisecondsSinceEpoch == ts);
        currentLastPrice = existing.close;
      }
      
      iterator = iterator.add(const Duration(minutes: 5));
    }

    if (addedAny) {
      list.sort((a, b) => a.timeStart.compareTo(b.timeStart));
      print('CandleRepository [$symbol]: Bootstrapped ${list.length} total nodes');
    }

    return list;
  }

  /// Helper to merge a new candle into an existing one, preserving orderflow data
  CandleModel _mergeCandle(CandleModel? existing, CandleModel incoming) {
    if (existing == null) return incoming;
    
    return incoming.copyWith(
      buyerCount: existing.buyerCount,
      sellerCount: existing.sellerCount,
      isBigSignal: existing.isBigSignal,
      isMediumSignal: existing.isMediumSignal,
      isInjected: existing.isInjected,
      injectedBy: existing.injectedBy,
      imbalances: existing.imbalances,
      footprint: existing.footprint,
    );
  }

  /// Connect to candle stream
  Future<void> connectStream(String token) async {
    await _webSocketDataSource.connect(token);
  }

  /// Subscribe to instruments
  void subscribeToInstrument(String symbol) {
    _webSocketDataSource.subscribe([symbol]);
  }

  /// Unsubscribe from instruments
  void unsubscribeFromInstrument(String symbol) {
    _webSocketDataSource.unsubscribe([symbol]);
  }

  /// Stream of candles
  Stream<CandleModel> get candleStream => _webSocketDataSource.candleStream;

  /// Stream of connection state
  Stream<WsConnectionState> get connectionStream => _webSocketDataSource.connectionStream;

  /// Stream of data source status
  Stream<DataSourceStatus> get dataSourceStream => _webSocketDataSource.dataSourceStream;

  /// Get cached candles
  Future<List<CandleModel>> getCachedCandles(String symbol) async {
    final cached = await _localCache.getCachedCandles(symbol);
    final cutoff = YahooDataSource.lastNTradingDaysStart(3);
    return cached.where((c) => !c.timeStart.isBefore(cutoff)).toList();
  }

  /// Cache candles
  Future<void> cacheCandles(String symbol, List<CandleModel> candles) async {
    await _localCache.cacheCandles(symbol, candles);
  }

  /// Add candle to cache
  Future<void> addCandleToCache(CandleModel candle) async {
    await _localCache.addCandle(candle.symbol, candle);
  }

  /// Disconnect
  Future<void> disconnect() async {
    await _webSocketDataSource.disconnect();
  }

  /// Wipe all historical candles for a symbol
  Future<void> wipeHistoricalCandles(String symbol) async {
    try {
      // 1. Wipe remote
      await _firebaseMarketDataSource.wipeHistoricalCandles(symbol);
      
      // 2. Wipe local cache
      await _localCache.cacheCandles(symbol, []);
      
      print('CandleRepository [$symbol]: Wiped remote and local data');
    } catch (e) {
      print('CandleRepository Error wiping candles: $e');
      rethrow;
    }
  }

  Future<List<CandleModel>> fetchCandlesForDate(String symbol, DateTime date) async {
    try {
      final fetched = await _yahooDataSource.fetchCandlesForDate(symbol, date);
      if (fetched.isNotEmpty) {
        return fetched;
      }
    } catch (e) {
      print('CandleRepository [$symbol]: Yahoo fetch for date failed: $e');
    }

    // Fallback: Generate full historical intraday 5m session nodes for chosen date (9:15 AM - 3:30 PM)
    print('CandleRepository [$symbol]: Generating historical session replay nodes for ${date.year}-${date.month}-${date.day}');
    final List<CandleModel> fallbackNodes = [];
    final marketStart = DateTime(date.year, date.month, date.day, 9, 15);
    final marketEnd = DateTime(date.year, date.month, date.day, 15, 40);

    final Map<String, double> seedPrices = {
      '^NSEI': 24200.0,
      '^NSEBANK': 52500.0,
      'NIFTY50': 24200.0,
      'BANKNIFTY': 52500.0,
      'FINNIFTY': 23400.0,
      'MIDCPNIFTY': 13100.0,
      'SENSEX': 79500.0,
    };
    double currentPrice = seedPrices[symbol.toUpperCase()] ?? 24000.0;
    DateTime iterator = marketStart;

    int index = 0;
    while (iterator.isBefore(marketEnd) || iterator.isAtSameMomentAs(marketEnd)) {
      final direction = (index % 2 == 0) ? 1.0 : -0.9;
      final bodySize = 12.0 + (index % 7) * 4.0;
      final wickSize = 5.0 + (index % 4) * 3.0;

      final openPrice = currentPrice;
      final closePrice = openPrice + (direction * bodySize);
      final highPrice = math.max(openPrice, closePrice) + wickSize;
      final lowPrice = math.min(openPrice, closePrice) - wickSize;
      final ts = iterator.millisecondsSinceEpoch;

      fallbackNodes.add(
        CandleModel(
          symbol: symbol,
          timeStart: iterator,
          timeEnd: iterator.add(const Duration(minutes: 5)),
          open: openPrice,
          high: highPrice,
          low: lowPrice,
          close: closePrice,
          volume: 5000 + (index % 11) * 1200,
          candleKey: ts.toString(),
        ),
      );

      currentPrice = closePrice;
      iterator = iterator.add(const Duration(minutes: 5));
      index++;
    }

    return fallbackNodes;
  }

  /// Public wrapper for generating bootstrap/placeholder candles immediately without network requests
  List<CandleModel> generateBootstrapCandles(String symbol, [List<CandleModel> currentCandles = const []]) {
    return _ensureLiveNode(symbol, currentCandles);
  }

  /// Stream Nifty 50 heatmap data
  Stream<Map<String, Map<String, dynamic>>> getHeatmapStream() {
    return _firebaseMarketDataSource.getHeatmapStream();
  }

  /// Stream the latest AI trade signal for an instrument
  Stream<Map<String, dynamic>?> getSignalStream(String instrument) {
    return _firebaseMarketDataSource.getSignalStream(instrument);
  }

  /// Fetch signal history for an instrument
  Future<List<Map<String, dynamic>>> getSignalHistory(String instrument) {
    return _firebaseMarketDataSource.getSignalHistory(instrument);
  }
}
