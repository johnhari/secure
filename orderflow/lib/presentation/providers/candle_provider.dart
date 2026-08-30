import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/candle_model.dart';
import '../../data/repositories/candle_repository.dart';
import '../../domain/entities/candle.dart';
import 'instrument_provider.dart';
import 'auth_provider.dart';
import 'providers.dart';
import '../../core/services/audio_service.dart';
import '../../core/constants/app_constants.dart';

/// Connection state for data source
enum DataConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// State for candle stream
class CandleStreamState {
  final List<CandleModel> candles;
  final DataConnectionState connectionState;
  final bool isLoading;
  final String? error;
  final DateTime? lastUpdated;
  final String? dataSourceInfo;
  // #8: offline banner
  final bool isOffline;
  
  // Replay fields
  final bool isReplaying;
  final bool isReplayPaused;
  final int replayIndex;
  final List<CandleModel> replayCandles;
  final int replaySpeed; // 1, 2, 3, 5

  const CandleStreamState({
    this.candles = const [],
    this.connectionState = DataConnectionState.disconnected,
    this.isLoading = false,
    this.error,
    this.lastUpdated,
    this.dataSourceInfo,
    this.isOffline = false,
    this.isReplaying = false,
    this.isReplayPaused = false,
    this.replayIndex = 0,
    this.replayCandles = const [],
    this.replaySpeed = 1,
  });

  CandleStreamState copyWith({
    List<CandleModel>? candles,
    DataConnectionState? connectionState,
    bool? isLoading,
    String? error,
    DateTime? lastUpdated,
    String? dataSourceInfo,
    bool? isOffline,
    bool? isReplaying,
    bool? isReplayPaused,
    int? replayIndex,
    List<CandleModel>? replayCandles,
    int? replaySpeed,
  }) {
    return CandleStreamState(
      candles: candles ?? this.candles,
      connectionState: connectionState ?? this.connectionState,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      dataSourceInfo: dataSourceInfo ?? this.dataSourceInfo,
      isOffline: isOffline ?? this.isOffline,
      isReplaying: isReplaying ?? this.isReplaying,
      isReplayPaused: isReplayPaused ?? this.isReplayPaused,
      replayIndex: replayIndex ?? this.replayIndex,
      replayCandles: replayCandles ?? this.replayCandles,
      replaySpeed: replaySpeed ?? this.replaySpeed,
    );
  }
}

/// Candle stream notifier using real-time WebSocket
class CandleStreamNotifier extends StateNotifier<CandleStreamState> {
  final Ref _ref;
  Timer? _pollingTimer;
  // #7: Token-refresh timer — Firebase ID tokens expire after 1h
  Timer? _tokenRefreshTimer;
  StreamSubscription? _candleSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _dataSourceSubscription;
  Timer? _replayTimer;

  late final CandleRepository _candleRepository;

  // #3: Track the calendar date at last fetch to detect date rollovers
  DateTime? _lastFetchDate;

  // #4: Track last orderflow sync time to avoid syncing too often
  DateTime? _lastOrderflowSync;
  Set<String> _lastSyncedCandleKeys = {};

  // Persistent in-memory cache of injected orderflows for the current instrument
  Map<String, Map<String, dynamic>> _injectedOrderflows = {};
  StreamSubscription? _orderflowSubscription;

  CandleStreamNotifier(this._ref) : super(const CandleStreamState()) {
    _candleRepository = _ref.read(candleRepositoryProvider);
    _initialize();
  }

  Future<void> _initialize() async {
    state = state.copyWith(
      isLoading: true,
      connectionState: DataConnectionState.connecting,
    );

    final symbol = _ref.read(selectedInstrumentProvider);

    // 1. Load from local cache first (Instant UI update)
    var cached = await _candleRepository.getCachedCandles(symbol);
    if (cached.isEmpty) {
      print('CandleStreamNotifier [$symbol]: Cache empty. Generating instant bootstrap data...');
      cached = _candleRepository.generateBootstrapCandles(symbol);
      await _candleRepository.cacheCandles(symbol, cached);
    } else {
      // Sort cached list chronologically to avoid issues from scrambled database cache
      cached = List<CandleModel>.from(cached)..sort((a, b) => a.timeStart.compareTo(b.timeStart));
    }

    state = state.copyWith(candles: cached, isLoading: false);
    _syncOrderflow(cached);
    print('CandleStreamNotifier [$symbol]: Loaded (${cached.length} candles)');

    // 2. Start Auth/WebSocket and Background Refresh immediately
    _handleAuthAndConnect();
    _startTokenRefreshTimer();

    // 3. Start fetching and seeding asynchronously in background without blocking UI
    _fetchAndSeedBackground(symbol);

    // 4. Start polling Yahoo every 45s for live updates
    _startPolling();

    // 5. Listen to repository streams for live data
    _candleSubscription = _candleRepository.candleStream.listen(_handleNewCandle);
    _connectionSubscription = _candleRepository.connectionStream.listen(_handleConnectionState);
    _dataSourceSubscription = _candleRepository.dataSourceStream.listen(_handleDataSourceStatus);

    // 6. Subscribe to real-time orderflow updates
    _setupOrderflowSubscription(symbol);
  }

  /// Helper to run initialization fetches asynchronously in the background.
  /// Prevents blocking the chart screen UI on cold startup.
  Future<void> _fetchAndSeedBackground(String symbol) async {
    try {
      final currentSymbol = _ref.read(selectedInstrumentProvider);
      if (currentSymbol != symbol) return;

      final cachedCount = state.candles.length;
      await Future.wait([
        // Seeding from Cloud Function (Only if cache is sparse)
        if (cachedCount < 50)
          _seedFromCloudFunction(symbol).timeout(const Duration(seconds: 15)),
          
        // Fresh Fetch from Yahoo & Firebase RTDB
        _fetchFromYahoo().timeout(const Duration(seconds: 12)),
      ]);
    } catch (e) {
      print('CandleStreamNotifier [$symbol]: Background fetch failed: $e');
    }
  }

  /// Helper to seed data from Cloud Function without blocking main initialization flow
  Future<void> _seedFromCloudFunction(String symbol) async {
    try {
      print('CandleStreamNotifier [$symbol]: Seeding via getMarketData...');
      final callable = FirebaseFunctions.instance.httpsCallable(
        'getMarketData',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
      );
      await callable.call<dynamic>({'symbol': symbol});
      
      final rtdbCandles = await _candleRepository.fetchHistoricalCandles(symbol);
      if (rtdbCandles.isNotEmpty) {
        // Dedup by 5-minute bucket
        final Map<int, CandleModel> bucketMap = {};
        for (final c in rtdbCandles) {
          final bucket = c.timeStart.millisecondsSinceEpoch ~/ (5 * 60 * 1000);
          if (!bucketMap.containsKey(bucket) || (c.buyerCount != null && c.buyerCount! > 0)) {
            bucketMap[bucket] = c;
          }
        }
        final dedupedRtdb = bucketMap.values.toList()
          ..sort((a, b) => a.timeStart.compareTo(b.timeStart));
        final mergedCandles = _mergeInjectedData(dedupedRtdb);
        if (mounted && _ref.read(selectedInstrumentProvider) == symbol) {
          state = state.copyWith(
            candles: mergedCandles,
            dataSourceInfo: 'FIREBASE SEED',
            lastUpdated: DateTime.now(),
          );
          _syncOrderflow(mergedCandles);
        }
        await _candleRepository.cacheCandles(symbol, dedupedRtdb);
      }
    } catch (e) {
      print('CandleStreamNotifier [$symbol]: Cloud Function seeding failed: $e');
    }
  }

  Future<void> _handleAuthAndConnect() async {
    final authState = _ref.read(authProvider);
    if (authState.isAuthenticated) {
      try {
        final token = await _ref.read(authRepositoryProvider).getIdToken();
        if (token != null) {
          await _candleRepository.connectStream(token);
          final symbol = _ref.read(selectedInstrumentProvider);
          _candleRepository.subscribeToInstrument(symbol);
        }
      } catch (e) {
        state = state.copyWith(error: 'Connection failed: $e');
      }
    }
  }

  // ── #7: Token refresh ────────────────────────────────────────────────────
  void _startTokenRefreshTimer() {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = Timer.periodic(const Duration(minutes: 50), (_) async {
      final authState = _ref.read(authProvider);
      if (!authState.isAuthenticated) return;
      try {
        // Force refresh so we get a new token before the old one expires
        final token =
            await _ref.read(authRepositoryProvider).getIdToken(forceRefresh: true);
        if (token != null) {
          await _candleRepository.connectStream(token);
          final symbol = _ref.read(selectedInstrumentProvider);
          _candleRepository.subscribeToInstrument(symbol);
        }
      } catch (e) {
        // Silent — will retry at next interval
      }
    });
  }

  void _handleConnectionState(dynamic wsState) {
    final String stateStr = wsState.toString();
    if (stateStr.contains('connected')) {
      state = state.copyWith(
        connectionState: DataConnectionState.connected,
        isOffline: false, // #8
      );
    } else if (stateStr.contains('connecting') || stateStr.contains('reconnecting')) {
      state = state.copyWith(connectionState: DataConnectionState.connecting);
    } else {
      state = state.copyWith(connectionState: DataConnectionState.disconnected);
    }
  }

  void _handleDataSourceStatus(dynamic status) {
    final info =
        '${status.type.toString().split('.').last.toUpperCase()}: ${status.message}';
    state = state.copyWith(dataSourceInfo: info);
  }

  void _handleNewCandle(CandleModel candle) {
    final symbol = _ref.read(selectedInstrumentProvider);
    if (candle.symbol != symbol) return;

    // Merge in-memory injected orderflow data
    final mergedCandle = _mergeInjectedData([candle]).first;

    var candlesList = List<CandleModel>.from(state.candles);
    if (candlesList.length < 25) {
      candlesList = _candleRepository.generateBootstrapCandles(symbol, candlesList);
    }
    // Primary match by candleKey
    int index = candlesList.indexWhere((c) => c.candleKey == mergedCandle.candleKey);

    // Secondary match by 5-minute time bucket (handles different keys, same slot)
    if (index == -1) {
      final incomingBucket = mergedCandle.timeStart.millisecondsSinceEpoch ~/ (5 * 60 * 1000);
      index = candlesList.indexWhere((c) =>
          (c.timeStart.millisecondsSinceEpoch ~/ (5 * 60 * 1000)) == incomingBucket);
    }

    if (index != -1) {
      final existing = candlesList[index];
      if (existing.close == mergedCandle.close &&
          existing.high == mergedCandle.high &&
          existing.low == mergedCandle.low &&
          existing.volume == mergedCandle.volume &&
          existing.buyerCount == mergedCandle.buyerCount &&
          existing.sellerCount == mergedCandle.sellerCount &&
          existing.isInjected == mergedCandle.isInjected) {
        return;
      }
      final buyerDiff = (mergedCandle.buyerCount ?? 0) - (existing.buyerCount ?? 0);
      final sellerDiff = (mergedCandle.sellerCount ?? 0) - (existing.sellerCount ?? 0);

      // Only trigger trade sound for major volume spikes, signals, or injections
      if (buyerDiff >= 5000 || sellerDiff >= 5000 || mergedCandle.isBigSignal || mergedCandle.isTrap || mergedCandle.isLiquidation) {
        AudioService.playTradeSound(isInstitutional: true);
      } else if (mergedCandle.isInjected && (buyerDiff > 0 || sellerDiff > 0)) {
        AudioService.playTradeSound(isInstitutional: false);
      }

      candlesList[index] = mergedCandle;
    } else {
      candlesList.add(mergedCandle);
      candlesList.sort((a, b) => a.timeStart.compareTo(b.timeStart));
      if (candlesList.length > AppConstants.maxCachedCandles) {
        candlesList.removeRange(0, candlesList.length - AppConstants.maxCachedCandles);
      }
    }

    state = state.copyWith(
      candles: candlesList,
      lastUpdated: DateTime.now(),
    );

    _candleRepository.addCandleToCache(mergedCandle);
  }

  Future<void> changeInstrument(String newSymbol, [String? oldSymbol]) async {
    if (oldSymbol != null) {
      _candleRepository.unsubscribeFromInstrument(oldSymbol);
    }

    _injectedOrderflows.clear();
    _setupOrderflowSubscription(newSymbol);

    state = state.copyWith(
      candles: [],
      isLoading: true,
      error: null,
    );

    var cached = await _candleRepository.getCachedCandles(newSymbol);
    if (cached.length < 25) {
      cached = _candleRepository.generateBootstrapCandles(newSymbol, cached);
    }
    final sortedCached = List<CandleModel>.from(cached)..sort((a, b) => a.timeStart.compareTo(b.timeStart));
    state = state.copyWith(
      candles: sortedCached,
      isLoading: false,
    );

    _candleRepository.subscribeToInstrument(newSymbol);
    _fetchFromYahoo();

    if (cached.isNotEmpty) {
      _syncOrderflow(cached);
    }
  }





  Future<void> _fetchFromYahoo() async {
    // Basic chart data (Yahoo) is allowed for everyone (guests included)
    // Only advanced Orderflow/WebSocket requires authentication
    if (state.isReplaying) return;
    final symbol = _ref.read(selectedInstrumentProvider);
    print('CandleStreamNotifier [$symbol]: Starting fetch cycle...');

    try {
      // Detect calendar date change
      final today = DateTime.now().toLocal();
      final todayDate = DateTime(today.year, today.month, today.day);
      if (_lastFetchDate != null && _lastFetchDate != todayDate) {
        print('CandleStreamNotifier [$symbol]: Date rollover detected, refreshing sync keys');
        _lastSyncedCandleKeys.clear();
        _lastOrderflowSync = null;
      }
      _lastFetchDate = todayDate;

      // This call now always returns at least bootstrapped nodes even if Yahoo fails
      var candles = await _candleRepository.fetchHistoricalCandles(symbol);
      if (candles.length < 25) {
        candles = _candleRepository.generateBootstrapCandles(symbol, candles);
      }

      if (candles.isNotEmpty) {
        // Final dedup by 5-minute bucket to prevent double candles from race
        // between polling and live stream updates
        final Map<int, CandleModel> bucketMap = {};
        for (final c in candles) {
          final bucket = c.timeStart.millisecondsSinceEpoch ~/ (5 * 60 * 1000);
          final existing = bucketMap[bucket];
          if (existing == null || (c.buyerCount != null && c.buyerCount! > 0)) {
            bucketMap[bucket] = c;
          }
        }
        final dedupedCandles = bucketMap.values.toList()
          ..sort((a, b) => a.timeStart.compareTo(b.timeStart));

        final mergedCandles = _mergeInjectedData(dedupedCandles);

        if (mounted && _ref.read(selectedInstrumentProvider) == symbol) {
          state = state.copyWith(
            candles: mergedCandles.length > AppConstants.maxCachedCandles
                ? mergedCandles.sublist(mergedCandles.length - AppConstants.maxCachedCandles)
                : mergedCandles,
            isLoading: false,
            dataSourceInfo: 'YAHOO (Polling Active)',
            lastUpdated: DateTime.now(),
            isOffline: false,
            error: null,
          );
          print('CandleStreamNotifier [$symbol]: State updated with ${mergedCandles.length} candles (deduped from ${candles.length})');
        }
      } else {
        if (mounted && _ref.read(selectedInstrumentProvider) == symbol) {
          state = state.copyWith(isLoading: false);
        }
      }
    } catch (e) {
      print('CandleStreamNotifier [$symbol]: Error in fetch cycle: $e');
      
      // FALLBACK: Always ensure a rich bootstrap history if fetch failed
      try {
        var cached = await _candleRepository.getCachedCandles(symbol);
        if (cached.length < 25) {
          cached = _candleRepository.generateBootstrapCandles(symbol, cached);
        }
        if (mounted && _ref.read(selectedInstrumentProvider) == symbol) {
          final sortedCached = List<CandleModel>.from(cached)..sort((a, b) => a.timeStart.compareTo(b.timeStart));
          state = state.copyWith(candles: sortedCached, isOffline: true, isLoading: false);
        }
      } catch (_) {}

      final isThrottled = e.toString().contains('THROTTLED');
      if (mounted && _ref.read(selectedInstrumentProvider) == symbol) {
        state = state.copyWith(
          isLoading: false, 
          isOffline: true,
          error: isThrottled 
            ? 'Yahoo Throttled: Too many requests. Please wait...' 
            : 'Failed to fetch data: $e'
        );
      }
    } finally {
      if (mounted && _ref.read(selectedInstrumentProvider) == symbol) {
        state = state.copyWith(isLoading: false);
      }
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    // Reduce polling frequency to avoid 429 errors from Yahoo
    _pollingTimer = Timer.periodic(const Duration(seconds: 45), (timer) {
      _fetchFromYahoo();
    });
  }

  List<CandleModel> _mergeInjectedData(List<CandleModel> incomingCandles) {
    if (_injectedOrderflows.isEmpty) return incomingCandles;
    return incomingCandles.map<CandleModel>((candle) {
      final tsKey = candle.timeStart.millisecondsSinceEpoch.toString();
      
      // 1. Try exact match by timestamp or candleKey
      var match = _injectedOrderflows[tsKey] ?? _injectedOrderflows[candle.candleKey];

      // 2. Fallback: Match by 5-minute bucket to handle non-aligned timestamps
      if (match == null) {
        final candleBucket = candle.timeStart.millisecondsSinceEpoch ~/ (5 * 60 * 1000);
        for (final entry in _injectedOrderflows.entries) {
          final entryTime = int.tryParse(entry.key);
          if (entryTime != null) {
            final entryBucket = entryTime ~/ (5 * 60 * 1000);
            if (entryBucket == candleBucket) {
              match = entry.value;
              break;
            }
          }
        }
      }

      if (match != null && match.isNotEmpty) {
        // Parse footprint if present
        Map<double, PriceLevelData>? footprint;
        final rawFootprint = match['footprint'] as Map<dynamic, dynamic>?;
        if (rawFootprint != null && rawFootprint.isNotEmpty) {
          footprint = {};
          rawFootprint.forEach((k, v) {
            if (v is Map) {
              final double? price = double.tryParse(k.toString());
              if (price != null) {
                footprint![price] = PriceLevelData(
                  buyVolume: (v['buyVolume'] as num?)?.toInt() ?? 0,
                  sellVolume: (v['sellVolume'] as num?)?.toInt() ?? 0,
                );
              }
            }
          });
        }

        return candle.copyWith(
          buyerCount: match['buyerCount'] as int?,
          sellerCount: match['sellerCount'] as int?,
          isBigSignal: match['isBigSignal'] as bool? ?? false,
          isMediumSignal: match['isMediumSignal'] as bool? ?? false,
          isTrap: match['isTrap'] as bool? ?? false,
          isLiquidation: match['isLiquidation'] as bool? ?? false,
          isInjected: true,
          injectedBy: match['injectedBy'] as String?,
          footprint: footprint,
        );
      }
      return candle;
    }).toList();
  }

  void _setupOrderflowSubscription(String symbol) {
    _orderflowSubscription?.cancel();
    final userEmail = _ref.read(authProvider).user?.email;
    _orderflowSubscription = _ref
        .read(orderflowServiceProvider)
        .getOrderflowStream(symbol, currentUserEmail: userEmail)
        .listen((orderflows) {
      _injectedOrderflows = orderflows;
      if (mounted && !state.isReplaying) {
        state = state.copyWith(candles: _mergeInjectedData(state.candles));
      }
    });
  }

  // ── #4: Throttled orderflow sync ─────────────────────────────────────────
  /// Only syncs when:
  ///   a) Never synced before, OR
  ///   b) New candle keys appeared since last sync, OR
  ///   c) More than 5 minutes have passed since last sync
  Future<void> _syncOrderflow(List<CandleModel> candles) async {
    final authState = _ref.read(authProvider);
    if (!authState.isAuthenticated) return;

    // Check if any new candle key appeared
    final currentKeys = {for (var c in candles) c.candleKey};
    final hasNewKeys = !_lastSyncedCandleKeys.containsAll(currentKeys);

    final now = DateTime.now();
    final timeSinceSync = _lastOrderflowSync == null
        ? const Duration(hours: 99)
        : now.difference(_lastOrderflowSync!);

    // Skip if nothing is new and we synced recently
    if (!hasNewKeys && timeSinceSync.inMinutes < 5) return;

    _lastOrderflowSync = now;
    _lastSyncedCandleKeys = currentKeys;

    try {
      final symbol = _ref.read(selectedInstrumentProvider);

      int? oldestTime;
      if (candles.isNotEmpty) {
        oldestTime = candles.first.timeStart.millisecondsSinceEpoch;
      }

      final userEmail = _ref.read(authProvider).user?.email;
      final orderflows = await _ref
          .read(orderflowServiceProvider)
          .getOrderflowData(symbol, startTime: oldestTime, currentUserEmail: userEmail);

      if (orderflows.isEmpty) return;

      _injectedOrderflows = {..._injectedOrderflows, ...orderflows};
      final updatedCandles = _mergeInjectedData(state.candles);

      if (mounted && _ref.read(selectedInstrumentProvider) == symbol) {
        state = state.copyWith(candles: updatedCandles);
      }

      await _candleRepository.cacheCandles(symbol, updatedCandles);
    } catch (e) {
      // Silently ignore sync errors
    }
  }


  Future<void> wipeHistoricalCandles(String symbol) async {
    try {
      await _candleRepository.wipeHistoricalCandles(symbol);
      
      // If wiping current symbol, clear state immediately
      final currentSymbol = _ref.read(selectedInstrumentProvider);
      if (symbol == currentSymbol) {
        state = state.copyWith(candles: []);
        _lastSyncedCandleKeys.clear();
        _lastOrderflowSync = null;
      }
    } catch (e) {
      print('CandleStreamNotifier Error wiping candles: $e');
      rethrow;
    }
  }

  // ── REPLAY SYSTEM ────────────────────────────────────────────────────────
  Future<void> startReplay(DateTime date) async {
    state = state.copyWith(isLoading: true, error: null);
    
    // 1. Pause active normal streams and polling
    _pollingTimer?.cancel();
    _candleSubscription?.cancel();
    _connectionSubscription?.cancel();
    _dataSourceSubscription?.cancel();
    _tokenRefreshTimer?.cancel();
    _replayTimer?.cancel();
    
    final symbol = _ref.read(selectedInstrumentProvider);
    
    try {
      print('CandleStreamNotifier [$symbol]: Starting Replay setup for ${date.toLocal()}');
      
      // 2. Fetch candles and orderflows for that day
      final fetchedCandles = await _candleRepository.fetchCandlesForDate(symbol, date);
      final userEmail = _ref.read(authProvider).user?.email;
      final orderflowData = await _ref
          .read(orderflowServiceProvider)
          .getOrderflowForDate(symbol, date, currentUserEmail: userEmail);
      
      if (fetchedCandles.isEmpty) {
        throw Exception('No market candles found for this date on $symbol.');
      }
      
      // Sort candles chronological
      fetchedCandles.sort((a, b) => a.timeStart.compareTo(b.timeStart));
      
      // 3. Merge candles with matching injected orderflow
      final mergedReplayCandles = fetchedCandles.map((candle) {
        final match = orderflowData[candle.timeStart.millisecondsSinceEpoch.toString()] ?? 
                      orderflowData[candle.candleKey];
        if (match != null && match.isNotEmpty) {
          return candle.copyWith(
            buyerCount: match['buyerCount'] as int?,
            sellerCount: match['sellerCount'] as int?,
            isBigSignal: match['isBigSignal'] as bool? ?? false,
            isMediumSignal: match['isMediumSignal'] as bool? ?? false,
            isInjected: true,
            injectedBy: match['injectedBy'] as String?,
          );
        }
        return candle;
      }).toList();
      
      print('CandleStreamNotifier [$symbol]: Loaded ${mergedReplayCandles.length} merged candles for replay.');
      
      // 4. Set state
      state = state.copyWith(
        isReplaying: true,
        isReplayPaused: false,
        replayIndex: 0,
        replayCandles: mergedReplayCandles,
        // Start by displaying only the first candle
        candles: [mergedReplayCandles.first],
        isLoading: false,
        dataSourceInfo: 'REPLAY ACTIVE',
        lastUpdated: DateTime.now(),
      );
      
      // 5. Start smooth playback timer
      _startReplayTimer();
    } catch (e) {
      print('CandleStreamNotifier [$symbol]: Replay start failed: $e');
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      // Restore normal stream
      await refresh();
      rethrow;
    }
  }

  void _startReplayTimer() {
    _replayTimer?.cancel();
    
    // Playback Speed mapping:
    // 1x = 1000ms, 2x = 500ms, 3x = 300ms, 5x = 100ms
    int intervalMs = 1000;
    if (state.replaySpeed == 2) intervalMs = 500;
    if (state.replaySpeed == 3) intervalMs = 300;
    if (state.replaySpeed == 5) intervalMs = 100;
    
    _replayTimer = Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      final nextIndex = state.replayIndex + 1;
      
      if (nextIndex >= state.replayCandles.length) {
        timer.cancel();
        state = state.copyWith(
          isReplayPaused: true,
          replayIndex: state.replayCandles.length - 1,
        );
        print('CandleStreamNotifier: Replay completed.');
        return;
      }
      
      final nextCandle = state.replayCandles[nextIndex];
      final candlesList = List<CandleModel>.from(state.candles);
      
      // Append next candle
      candlesList.add(nextCandle);
      
      // Trigger sounds and haptics for orderflow in replay!
      _triggerReplayEffects(nextCandle);
      
      state = state.copyWith(
        candles: candlesList,
        replayIndex: nextIndex,
        lastUpdated: DateTime.now(),
      );
    });
  }

  void _triggerReplayEffects(CandleModel candle) {
    if (candle.buyerCount != null || candle.sellerCount != null) {
      final isBig = candle.isBigSignal;
      final isHeavy = (candle.buyerCount ?? 0) >= 5000 || (candle.sellerCount ?? 0) >= 5000;
      
      if (isBig || isHeavy) {
        AudioService.playTradeSound(isInstitutional: true);
      } else {
        AudioService.playTradeSound(isInstitutional: false);
      }
    }
  }

  void pauseReplay() {
    _replayTimer?.cancel();
    state = state.copyWith(isReplayPaused: true);
  }

  void resumeReplay() {
    state = state.copyWith(isReplayPaused: false);
    _startReplayTimer();
  }

  void stepReplay() {
    if (!state.isReplaying) return;
    
    final nextIndex = state.replayIndex + 1;
    if (nextIndex >= state.replayCandles.length) return;
    
    final nextCandle = state.replayCandles[nextIndex];
    final candlesList = state.replayCandles.sublist(0, nextIndex + 1);
    
    _triggerReplayEffects(nextCandle);
    
    state = state.copyWith(
      candles: candlesList,
      replayIndex: nextIndex,
      lastUpdated: DateTime.now(),
    );
  }

  void stepBackwardReplay() {
    if (!state.isReplaying) return;
    
    final prevIndex = state.replayIndex - 1;
    if (prevIndex < 0) return;
    
    final candlesList = state.replayCandles.sublist(0, prevIndex + 1);
    
    state = state.copyWith(
      candles: candlesList,
      replayIndex: prevIndex,
      lastUpdated: DateTime.now(),
    );
  }

  void seekReplay(int index) {
    if (!state.isReplaying) return;
    final targetIndex = index.clamp(0, state.replayCandles.length - 1);
    
    final candlesList = state.replayCandles.sublist(0, targetIndex + 1);
    
    if (targetIndex > state.replayIndex) {
      _triggerReplayEffects(state.replayCandles[targetIndex]);
    }
    
    state = state.copyWith(
      candles: candlesList,
      replayIndex: targetIndex,
      lastUpdated: DateTime.now(),
    );
  }

  void setReplaySpeed(int speed) {
    state = state.copyWith(replaySpeed: speed);
    if (state.isReplaying && !state.isReplayPaused) {
      _startReplayTimer();
    }
  }

  Future<void> exitReplay() async {
    _replayTimer?.cancel();
    state = state.copyWith(
      isReplaying: false,
      isReplayPaused: false,
      replayIndex: 0,
      replayCandles: const [],
      candles: const [],
    );
    
    print('CandleStreamNotifier: Exited replay mode. Restoring normal stream...');
    await refresh(clearCache: true);
  }

  Future<void> refresh({bool clearCache = false}) async {
    state = state.copyWith(isLoading: true, error: null);
    
    _pollingTimer?.cancel();
    _candleSubscription?.cancel();
    _connectionSubscription?.cancel();
    _dataSourceSubscription?.cancel();
    _tokenRefreshTimer?.cancel();
    _replayTimer?.cancel();
    _orderflowSubscription?.cancel();
    
    if (clearCache) {
      final symbol = _ref.read(selectedInstrumentProvider);
      await _candleRepository.cacheCandles(symbol, []);
      _lastSyncedCandleKeys.clear();
      _lastOrderflowSync = null;
    }
    
    await _initialize();
  }

  @override
  void dispose() {
    _candleSubscription?.cancel();
    _connectionSubscription?.cancel();
    _dataSourceSubscription?.cancel();
    _pollingTimer?.cancel();
    _tokenRefreshTimer?.cancel(); // #7
    _replayTimer?.cancel();
    _orderflowSubscription?.cancel();
    super.dispose();
  }
}

/// Provider for candle stream
final candleStreamProvider =
    StateNotifierProvider<CandleStreamNotifier, CandleStreamState>((ref) {
  final notifier = CandleStreamNotifier(ref);

  // React to instrument changes
  ref.listen<String>(selectedInstrumentProvider, (previous, next) {
    notifier.changeInstrument(next, previous);
  });

  return notifier;
});
