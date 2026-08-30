import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/candle_model.dart';

/// Yahoo Finance API datasource for free Nifty50/BankNifty data
class YahooFinanceDataSource {
  static const String _baseUrl = 'https://query1.finance.yahoo.com/v8/finance/chart';
  
  // Yahoo Finance symbols
  static const Map<String, String> symbols = {
    'NIFTY50': '^NSEI',
    'BANKNIFTY': '^NSEBANK',
  };

  Timer? _pollingTimer;
  final _candleController = StreamController<CandleModel>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  
  String _currentSymbol = 'NIFTY50';
  List<CandleModel> _candles = [];
  bool _isConnected = false;

  Stream<CandleModel> get candleStream => _candleController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  List<CandleModel> get candles => List.unmodifiable(_candles);
  bool get isConnected => _isConnected;

  /// Start fetching data for a symbol
  Future<void> connect(String symbol) async {
    _currentSymbol = symbol;
    
    // Fetch initial historical data
    await _fetchHistoricalData();
    
    // Start polling for live updates
    _startPolling();
    
    _isConnected = true;
    _connectionController.add(true);
  }

  /// Change to a different symbol
  Future<void> changeSymbol(String symbol) async {
    if (_currentSymbol == symbol) return;
    
    _currentSymbol = symbol;
    _candles.clear();
    
    await _fetchHistoricalData();
  }

  /// Fetch historical candles (last 1-5 days)
  Future<void> _fetchHistoricalData() async {
    try {
      final yahooSymbol = symbols[_currentSymbol] ?? '^NSEI';
      final url = '$_baseUrl/$yahooSymbol?interval=5m&range=3d&includePrePost=false';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _parseAndEmitCandles(data);
      }
    } catch (e) {
      print('Yahoo Finance fetch error: $e');
    }
  }

  /// Parse Yahoo Finance response and emit candles
  void _parseAndEmitCandles(Map<String, dynamic> data) {
    try {
      final result = data['chart']?['result']?[0];
      if (result == null) return;

      final timestamps = result['timestamp'] as List?;
      final quote = result['indicators']?['quote']?[0];
      
      if (timestamps == null || quote == null) return;

      final opens = quote['open'] as List?;
      final highs = quote['high'] as List?;
      final lows = quote['low'] as List?;
      final closes = quote['close'] as List?;
      final volumes = quote['volume'] as List?;

      if (opens == null || highs == null || lows == null || closes == null) return;

      final newCandles = <CandleModel>[];

      for (int i = 0; i < timestamps.length; i++) {
        final timestamp = timestamps[i] as int?;
        final open = opens[i];
        final high = highs[i];
        final low = lows[i];
        final close = closes[i];
        final volume = volumes?[i];

        // Skip null values
        if (timestamp == null || open == null || high == null || 
            low == null || close == null) {
          continue;
        }

        final timeStartDt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
        final candleKey = '${_currentSymbol}_5m_$timestamp';
        
        final candle = CandleModel(
          symbol: _currentSymbol,
          candleKey: candleKey,
          timeStart: timeStartDt,
          timeEnd: DateTime.fromMillisecondsSinceEpoch((timestamp + 300) * 1000),
          open: (open as num).toDouble(),
          high: (high as num).toDouble(),
          low: (low as num).toDouble(),
          close: (close as num).toDouble(),
          volume: (volume as num?)?.toInt() ?? 0,
        );

        newCandles.add(candle);
      }

      // Update candles list
      _candles = newCandles;
      
      // Sort by time
      _candles.sort((a, b) => a.timeStart.compareTo(b.timeStart));

      // Emit each candle
      for (final candle in _candles) {
        _candleController.add(candle);
      }
    } catch (e) {
      print('Parse error: $e');
    }
  }

  /// Start polling for live updates
  void _startPolling() {
    _pollingTimer?.cancel();
    
    // Poll every 5 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _fetchLatestQuote();
    });
  }

  /// Fetch latest quote and update last candle
  Future<void> _fetchLatestQuote() async {
    try {
      final yahooSymbol = symbols[_currentSymbol] ?? '^NSEI';
      final url = '$_baseUrl/$yahooSymbol?interval=1m&range=1d&includePrePost=false';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _updateLatestCandle(data);
      }
    } catch (e) {
      print('Poll error: $e');
    }
  }

  /// Update the latest candle with new data
  void _updateLatestCandle(Map<String, dynamic> data) {
    try {
      final result = data['chart']?['result']?[0];
      if (result == null) return;

      final meta = result['meta'];
      final regularMarketPrice = meta?['regularMarketPrice'] as num?;
      
      if (regularMarketPrice == null || _candles.isEmpty) return;

      final price = regularMarketPrice.toDouble();
      final lastCandle = _candles.last;
      
      // Calculate which 5-minute bucket we're in
      final now = DateTime.now();
      final currentBucketStart = DateTime(
        now.year, now.month, now.day, 
        now.hour, (now.minute ~/ 5) * 5
      );

      // Check if we need a new candle or update existing
      if (lastCandle.timeStart.isBefore(currentBucketStart)) {
        // Create new candle
        final candleKey = '${_currentSymbol}_5m_${currentBucketStart.millisecondsSinceEpoch ~/ 1000}';
        final newCandle = CandleModel(
          symbol: _currentSymbol,
          candleKey: candleKey,
          timeStart: currentBucketStart,
          timeEnd: currentBucketStart.add(const Duration(minutes: 5)),
          open: price,
          high: price,
          low: price,
          close: price,
          volume: 0,
        );
        _candles.add(newCandle);
        _candleController.add(newCandle);
      } else {
        // Update existing candle
        final updatedCandle = CandleModel(
          symbol: lastCandle.symbol,
          candleKey: lastCandle.candleKey,
          timeStart: lastCandle.timeStart,
          timeEnd: lastCandle.timeEnd,
          open: lastCandle.open,
          high: price > lastCandle.high ? price : lastCandle.high,
          low: price < lastCandle.low ? price : lastCandle.low,
          close: price,
          volume: lastCandle.volume,
          buyerCount: lastCandle.buyerCount,
          sellerCount: lastCandle.sellerCount,
        );
        _candles[_candles.length - 1] = updatedCandle;
        _candleController.add(updatedCandle);
      }
    } catch (e) {
      print('Update error: $e');
    }
  }

  /// Disconnect and clean up
  void disconnect() {
    _pollingTimer?.cancel();
    _isConnected = false;
    _connectionController.add(false);
  }

  /// Dispose resources
  void dispose() {
    disconnect();
    _candleController.close();
    _connectionController.close();
  }
}
