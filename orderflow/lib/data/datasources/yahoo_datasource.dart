import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/candle_model.dart';

class YahooDataSource {
  final http.Client _client;

  YahooDataSource({http.Client? client}) : _client = client ?? http.Client();

  /// Maps local NSE instrument symbols to their Yahoo Finance tickers
  static const Map<String, String> yahooSymbolMap = {
    'NIFTY50': '^NSEI',
    'BANKNIFTY': '^NSEBANK',
    'FINNIFTY': '^CNXFIN',
    'MIDCAPNIFTY': '^NSEMDCP50',
    'MIDCPNIFTY': '^NSMIDCP',
    'NIFTYNXT50': '^NSMIDCP',
    'INDIA_VIX': '^INDIAVIX',
    'SENSEX': '^BSESN',
    'NIFTYIT': '^CNXIT',
    'NIFTYAUTO': '^CNXAUTO',
    'NIFTYMETAL': '^CNXMETAL',
    'NIFTYPHARMA': '^CNXPHARMA',
    'NIFTYFMCG': '^CNXFMCG',
    'NIFTYINFRA': '^CNXINFRA',
    'NIFTYENERGY': '^CNXENERGY',
    'NIFTYMEDIA': '^CNXMEDIA',
    'NIFTYREALTY': '^CNXREALTY',
    'NIFTYPSE': '^CNXPSE',
  };

  /// NSE market open/close in IST (hours, minutes)
  static const int _marketOpenHour = 9;
  static const int _marketOpenMinute = 15;
  static const int _marketCloseHour = 15;
  static const int _marketCloseMinute = 40;

  // ── #1: NSE Exchange Holidays 2025-2026 ───────────────────────────────────
  // Dates are in IST (local). Add each year's NSE holiday calendar here.
  // Source: https://www.nseindia.com/resources/exchange-communication-holidays
  static final Set<String> _nseHolidays = {
    // 2025
    '2025-01-26', // Republic Day
    '2025-02-26', // Mahashivratri
    '2025-03-14', // Holi
    '2025-04-10', // Ram Navami
    '2025-04-14', // Dr. Ambedkar Jayanti / Mahavir Jayanti
    '2025-04-18', // Good Friday
    '2025-05-01', // Maharashtra Day
    '2025-08-15', // Independence Day
    '2025-08-27', // Ganesh Chaturthi
    '2025-10-02', // Gandhi Jayanti / Dussehra
    '2025-10-20', // Diwali Laxmi Puja (Muhurat trading only)
    '2025-10-21', // Diwali Balipratipada
    '2025-11-05', // Prakash Gurpurab
    '2025-12-25', // Christmas
    // 2026
    '2026-01-26', // Republic Day
    '2026-03-03', // Mahashivratri
    '2026-03-20', // Holi
    '2026-04-02', // Ram Navami
    '2026-04-03', // Good Friday
    '2026-04-14', // Dr. Ambedkar Jayanti
    '2026-05-01', // Maharashtra Day
    '2026-08-15', // Independence Day
    '2026-10-02', // Gandhi Jayanti
    '2026-12-25', // Christmas
  };

  /// Returns true if the given date is an NSE holiday
  static bool isNseHoliday(DateTime date) {
    final key =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return _nseHolidays.contains(key);
  }

  /// Returns true if the given local DateTime is an NSE trading day
  static bool isTradingDay(DateTime date) {
    // weekday: Mon=1…Fri=5, Sat=6, Sun=7
    if (date.weekday > 5) return false;
    if (isNseHoliday(date)) return false;
    return true;
  }

  /// Returns true if the given DateTime falls within NSE trading hours (IST)
  bool _isWithinMarketHours(DateTime time) {
    // Convert to IST (UTC+5:30)
    final istTime = time.toUtc().add(const Duration(hours: 5, minutes: 30));
    
    const openMinutes = _marketOpenHour * 60 + _marketOpenMinute;
    const closeMinutes = _marketCloseHour * 60 + _marketCloseMinute;
    final candleMinutes = istTime.hour * 60 + istTime.minute;
    
    return candleMinutes >= openMinutes && candleMinutes < closeMinutes;
  }

  // ── #1 + #5: Compute last N trading days (weekday & holiday-aware) ──────────
  /// Returns the start of the Nth-last trading day as a [DateTime] (midnight IST).
  /// Skips weekends AND NSE holidays.
  ///
  /// Examples:
  ///   Sunday Mar 2  → Fri Feb 28 & Thu Feb 27  → cutoff = Feb 27 00:00
  ///   Monday Mar 3  → Fri Feb 28 & Thu Feb 27  → cutoff = Feb 27 00:00
  ///   Holi (Fri)    → Thu & Wed of same week   → correct
  static DateTime lastNTradingDaysStart(int n, [DateTime? relativeTo]) {
    final base = relativeTo ?? DateTime.now().toLocal();
    DateTime candidate = DateTime(base.year, base.month, base.day);

    final List<DateTime> tradingDays = [];
    while (tradingDays.length < n) {
      if (isTradingDay(candidate)) {
        tradingDays.add(candidate);
      }
      candidate = candidate.subtract(const Duration(days: 1));
    }
    // tradingDays[n-1] is the oldest → use as cutoff
    return tradingDays.last;
  }

  static final List<String> _userAgents = [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_3_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1',
  ];

  static int _uaIndex = 0;

  String _getNextUserAgent() {
    final ua = _userAgents[_uaIndex];
    _uaIndex = (_uaIndex + 1) % _userAgents.length;
    return ua;
  }

  /// Fetch historical candles from Yahoo Finance.
  Future<List<CandleModel>> fetchHistoricalCandles(String symbol) async {
    try {
      var yahooSymbol = yahooSymbolMap[symbol];
      if (yahooSymbol == null) {
        if (symbol.startsWith('^') || symbol.endsWith('.NS')) {
          yahooSymbol = symbol;
        } else {
          yahooSymbol = '$symbol.NS';
        }
      }

      // Compute exact epoch window
      final cutoff = lastNTradingDaysStart(3);
      final period1 = cutoff.millisecondsSinceEpoch ~/ 1000;
      final period2 = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Try query2 first as it's often less throttled
      return await _fetchWithRetry(yahooSymbol, symbol, period1, period2, cutoff);
    } catch (e) {
      print('YahooDataSource Error: $e');
      return [];
    }
  }

  Future<List<CandleModel>> _fetchWithRetry(
    String yahooSymbol, 
    String originalSymbol,
    int period1, 
    int period2, 
    DateTime cutoff
  ) async {
    // Attempt 1: query2 with period1/period2
    var candles = await _makeRequest(
      'https://query2.finance.yahoo.com/v8/finance/chart/$yahooSymbol?interval=5m&period1=$period1&period2=$period2',
      originalSymbol,
      cutoff,
    );

    if (candles.isNotEmpty) return candles;

    // Attempt 2: query2 with range=10d (Very reliable for intraday)
    candles = await _makeRequest(
      'https://query2.finance.yahoo.com/v8/finance/chart/$yahooSymbol?interval=5m&range=10d',
      originalSymbol,
      cutoff,
    );
    
    if (candles.isNotEmpty) return candles;

    // Attempt 3: query1 with range=7d (fallback endpoint)
    candles = await _makeRequest(
      'https://query1.finance.yahoo.com/v8/finance/chart/$yahooSymbol?interval=5m&range=7d',
      originalSymbol,
      cutoff,
    );

    return candles;
  }

  Future<List<CandleModel>> _makeRequest(String url, String originalSymbol, DateTime cutoff) async {
    try {
      http.Response? response;
      
      if (kIsWeb) {
        // Layer 1: AllOrigins Raw
        final proxyUrl1 = 'https://api.allorigins.win/raw?url=${Uri.encodeComponent(url)}';
        try {
          response = await _client.get(Uri.parse(proxyUrl1)).timeout(const Duration(seconds: 8));
        } catch (_) {}

        // Layer 2: CorsProxy.io
        if (response == null || response.statusCode != 200) {
          final proxyUrl2 = 'https://corsproxy.io/?${Uri.encodeComponent(url)}';
          try {
            response = await _client.get(Uri.parse(proxyUrl2)).timeout(const Duration(seconds: 8));
          } catch (_) {}
        }

        // Layer 3: CodeTabs (Fast fallback)
        if (response == null || response.statusCode != 200) {
          final proxyUrl3 = 'https://api.codetabs.com/v1/proxy?quest=${Uri.encodeComponent(url)}';
          try {
             response = await _client.get(Uri.parse(proxyUrl3)).timeout(const Duration(seconds: 8));
          } catch (_) {}
        }
        
        // Layer 4: AllOrigins API (JSON Wrapped)
        if (response == null || response.statusCode != 200) {
          final proxyUrl4 = 'https://api.allorigins.win/get?url=${Uri.encodeComponent(url)}';
          try {
            final res = await _client.get(Uri.parse(proxyUrl4)).timeout(const Duration(seconds: 8));
            if (res.statusCode == 200) {
              final jsonMap = jsonDecode(res.body);
              if (jsonMap['contents'] != null) {
                response = http.Response(jsonMap['contents'], 200);
              }
            }
          } catch (_) {}
        }
      }

      // Final Layer: Native fetch (Android/iOS) or Last-ditch direct (Web)
      if (response == null || response.statusCode != 200) {
        // Browsers block Origin/Referer headers in JS, only set them on Native
        final Map<String, String> headers = kIsWeb ? {
          'Accept': '*/*',
          'User-Agent': _getNextUserAgent(),
        } : {
          'User-Agent': _getNextUserAgent(),
          'Accept': '*/*',
          'Origin': 'https://finance.yahoo.com',
          'Referer': 'https://finance.yahoo.com/quote/^NSEI',
        };

        response = await _client.get(
          Uri.parse(url),
          headers: headers,
        ).timeout(const Duration(seconds: 12));
      }

      if (response.statusCode == 429) {
        print('YahooDataSource: Throttled (429) for $url');
        return []; // Return empty instead of throwing to allow repo fallback
      }

      if (response.statusCode != 200) {
        print('YahooDataSource: Error ${response.statusCode} for $url');
        return [];
      }

      final data = jsonDecode(response.body);
      final result = data['chart']?['result']?[0];
      if (result == null) return [];

      final meta = result['meta'];
      final double? regularMarketPrice = (meta?['regularMarketPrice'] as num?)?.toDouble();

      final quote = result['indicators']?['quote']?[0];
      final timestamps = result['timestamp'];
      if (timestamps == null || quote == null) return [];

      final opens = List<dynamic>.from(quote['open'] ?? []);
      final highs = List<dynamic>.from(quote['high'] ?? []);
      final lows = List<dynamic>.from(quote['low'] ?? []);
      final closes = List<dynamic>.from(quote['close'] ?? []);
      final volumes = List<dynamic>.from(quote['volume'] ?? []);

      final List<CandleModel> candles = [];

      for (var i = 0; i < (timestamps as List).length; i++) {
        if (i >= opens.length || opens[i] == null ||
            i >= highs.length || highs[i] == null ||
            i >= lows.length || lows[i] == null ||
            i >= closes.length || closes[i] == null) {
          continue;
        }

        final timestamp = (timestamps[i] as int) * 1000;
        final timeStart = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
        
        if (!_isWithinMarketHours(timeStart)) continue;
        if (timeStart.isBefore(cutoff)) continue;

        candles.add(CandleModel(
          symbol: originalSymbol,
          timeStart: timeStart,
          timeEnd: timeStart.add(const Duration(minutes: 5)),
          open: (opens[i] as num).toDouble(),
          high: (highs[i] as num).toDouble(),
          low: (lows[i] as num).toDouble(),
          close: (closes[i] as num).toDouble(),
          volume: i < volumes.length ? (volumes[i] as num?)?.toInt() ?? 0 : 0,
          candleKey: timestamp.toString(),
        ));
      }

      if (candles.isNotEmpty && regularMarketPrice != null && regularMarketPrice > 0) {
        final lastCandle = candles.last;
        final timeDiff = DateTime.now().difference(lastCandle.timeStart).inMinutes.abs();
        if (timeDiff < 1440) {
          candles[candles.length - 1] = lastCandle.copyWith(
            close: regularMarketPrice,
            high: regularMarketPrice > lastCandle.high ? regularMarketPrice : lastCandle.high,
            low: regularMarketPrice < lastCandle.low ? regularMarketPrice : lastCandle.low,
          );
        }
      }

      return candles;
    } catch (e) {
      print('YahooDataSource request error: $e');
      return [];
    }
  }

  Future<List<CandleModel>> fetchCandlesForDate(String symbol, DateTime date) async {
    try {
      var yahooSymbol = yahooSymbolMap[symbol];
      if (yahooSymbol == null) {
        if (symbol.startsWith('^') || symbol.endsWith('.NS')) {
          yahooSymbol = symbol;
        } else {
          yahooSymbol = '$symbol.NS';
        }
      }
      
      // Calculate IST start/end of the chosen date
      final start = DateTime(date.year, date.month, date.day, 0, 0, 0);
      final end = DateTime(date.year, date.month, date.day, 23, 59, 59);
      
      final p1 = start.millisecondsSinceEpoch ~/ 1000;
      final p2 = end.millisecondsSinceEpoch ~/ 1000;
      
      // Call standard _fetchWithRetry which checks isWithinMarketHours and filters automatically
      return await _fetchWithRetry(yahooSymbol, symbol, p1, p2, start);
    } catch (e) {
      print('YahooDataSource fetchCandlesForDate Error: $e');
      return [];
    }
  }
}
