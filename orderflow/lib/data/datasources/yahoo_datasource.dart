import 'dart:convert';
import 'dart:math' as math;
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

  /// NSE trading hours in IST (09:15 to 15:40 IST, 3:40 PM)
  /// Last 5m candle starts at 15:35 and closes at 15:40.
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
  /// Market session runs from 09:15 to 15:40 IST (3:40 PM).
  static bool isWithinMarketHours(DateTime time) {
    // Convert to IST (UTC+5:30)
    final istTime = time.toUtc().add(const Duration(hours: 5, minutes: 30));
    if (!isTradingDay(istTime)) return false;
    
    const openMinutes = _marketOpenHour * 60 + _marketOpenMinute; // 555 (09:15)
    const closeMinutes = _marketCloseHour * 60 + _marketCloseMinute; // 940 (15:40)
    final candleMinutes = istTime.hour * 60 + istTime.minute;
    
    // Valid trading hours are 09:15 (555) through 15:40 (940)
    return candleMinutes >= openMinutes && candleMinutes <= closeMinutes;
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

  Future<List<CandleModel>> _fetchFromCloudFunction(String symbol) async {
    try {
      final uri = Uri.parse('https://us-central1-mst7-3fb55.cloudfunctions.net/apiMarketData?symbol=$symbol');
      final response = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = (data is Map && data['candles'] is List) 
            ? data['candles'] as List 
            : (data is List ? data : null);
        if (list != null && list.isNotEmpty) {
          final List<CandleModel> result = [];
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              result.add(CandleModel.fromJson(item));
            } else if (item is Map) {
              result.add(CandleModel.fromJson(Map<String, dynamic>.from(item)));
            }
          }
          if (result.isNotEmpty) {
            print('YahooDataSource [$symbol]: Successfully fetched ${result.length} live candles from Cloud Function');
            return result;
          }
        }
      }
    } catch (e) {
      print('YahooDataSource [$symbol]: Cloud Function fetch error: $e');
    }
    return [];
  }

  /// Fetch historical candles from Yahoo Finance.
  Future<List<CandleModel>> fetchHistoricalCandles(String symbol) async {
    try {
      // 1. On Web, Cloud Function is primary to bypass browser CORS completely
      if (kIsWeb) {
        final cfCandles = await _fetchFromCloudFunction(symbol);
        if (cfCandles.isNotEmpty) {
          final cutoff = lastNTradingDaysStart(3);
          return cfCandles.where((c) => !c.timeStart.isBefore(cutoff)).toList();
        }
      }

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

      // Try query2/query1 first on native
      var candles = await _fetchWithRetry(yahooSymbol, symbol, period1, period2, cutoff);
      if (candles.isNotEmpty) return candles;

      // Fallback to Cloud Function if direct Yahoo was throttled/failed on native
      final cfCandles = await _fetchFromCloudFunction(symbol);
      if (cfCandles.isNotEmpty) {
        return cfCandles.where((c) => !c.timeStart.isBefore(cutoff)).toList();
      }

      return [];
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

      final Map<int, CandleModel> bucketMap = {};

      for (var i = 0; i < (timestamps as List).length; i++) {
        if (i >= opens.length || opens[i] == null ||
            i >= highs.length || highs[i] == null ||
            i >= lows.length || lows[i] == null ||
            i >= closes.length || closes[i] == null) {
          continue;
        }

        final rawTimestamp = (timestamps[i] as int) * 1000;
        final rawTime = DateTime.fromMillisecondsSinceEpoch(rawTimestamp).toLocal();
        final istTime = rawTime.toUtc().add(const Duration(hours: 5, minutes: 30));
        
        if (!isTradingDay(istTime)) continue;
        if (rawTime.isBefore(cutoff)) continue;

        final candleMinutes = istTime.hour * 60 + istTime.minute;
        if (candleMinutes < 555) continue; // Skip pre-market data before 09:15 IST

        // In NSE, trading and closing session runs until 15:40 IST (940 min).
        // Any post-close tick arriving at or after 15:40 belongs to the session closing candle.
        final int bucketMs;
        if (candleMinutes >= 940) {
          bucketMs = (rawTimestamp ~/ (5 * 60 * 1000)) * (5 * 60 * 1000) - ((candleMinutes ~/ 5 - 187) * 5 * 60 * 1000);
        } else {
          bucketMs = (rawTimestamp ~/ (5 * 60 * 1000)) * (5 * 60 * 1000);
        }
        final timeStart = DateTime.fromMillisecondsSinceEpoch(bucketMs).toLocal();

        final o = (opens[i] as num).toDouble();
        final h = (highs[i] as num).toDouble();
        final l = (lows[i] as num).toDouble();
        final c = (closes[i] as num).toDouble();
        final v = i < volumes.length ? (volumes[i] as num?)?.toInt() ?? 0 : 0;

        final existing = bucketMap[bucketMs];
        if (existing == null) {
          bucketMap[bucketMs] = CandleModel(
            symbol: originalSymbol,
            timeStart: timeStart,
            timeEnd: timeStart.add(const Duration(minutes: 5)),
            open: o,
            high: h,
            low: l,
            close: c,
            volume: v,
            candleKey: bucketMs.toString(),
          );
        } else {
          bucketMap[bucketMs] = existing.copyWith(
            high: math.max(existing.high, h),
            low: math.min(existing.low, l),
            close: c,
            volume: existing.volume + v,
          );
        }
      }

      final List<CandleModel> candles = bucketMap.values.toList()
        ..sort((a, b) => a.timeStart.compareTo(b.timeStart));

      // ── Apply official NSE EOD close to latest session ──
      if (candles.isNotEmpty && regularMarketPrice != null && regularMarketPrice > 0) {
        final lastCandle = candles.last;
        final now = DateTime.now();
        final istNow = now.toUtc().add(const Duration(hours: 5, minutes: 30));
        final nowMinute = istNow.hour * 60 + istNow.minute;
        final isToday = lastCandle.timeStart.year == now.year &&
            lastCandle.timeStart.month == now.month &&
            lastCandle.timeStart.day == now.day;
        
        if (isToday && nowMinute < 940 && isTradingDay(istNow)) {
          // Market is currently live (< 15:40 IST)
          final nowBucketMs = (now.millisecondsSinceEpoch ~/ (5 * 60 * 1000)) * (5 * 60 * 1000);
          if (nowBucketMs > lastCandle.timeStart.millisecondsSinceEpoch) {
            final formingTime = DateTime.fromMillisecondsSinceEpoch(nowBucketMs).toLocal();
            final formingIst = formingTime.toUtc().add(const Duration(hours: 5, minutes: 30));
            final formingMinutes = formingIst.hour * 60 + formingIst.minute;
            // Only add forming candle if its start time is strictly <= 15:35 IST (closing at 15:40)
            if (formingMinutes <= 935) {
              candles.add(CandleModel(
                symbol: originalSymbol,
                timeStart: formingTime,
                timeEnd: formingTime.add(const Duration(minutes: 5)),
                open: lastCandle.close,
                high: math.max(lastCandle.close, regularMarketPrice),
                low: math.min(lastCandle.close, regularMarketPrice),
                close: regularMarketPrice,
                volume: 0,
                candleKey: nowBucketMs.toString(),
              ));
            }
          } else {
            candles[candles.length - 1] = lastCandle.copyWith(
              close: regularMarketPrice,
              high: regularMarketPrice > lastCandle.high ? regularMarketPrice : lastCandle.high,
              low: regularMarketPrice < lastCandle.low ? regularMarketPrice : lastCandle.low,
            );
          }
        } else {
          // Market is closed (after 15:40 IST, or on weekends/holidays):
          // Update the final EOD candle of the latest session with the official NSE close!
          candles[candles.length - 1] = lastCandle.copyWith(
            close: regularMarketPrice,
            high: regularMarketPrice > lastCandle.high ? regularMarketPrice : lastCandle.high,
            low: regularMarketPrice < lastCandle.low ? regularMarketPrice : lastCandle.low,
          );
        }
      }

      // ── Apply official NSE EOD close to previous completed trading day from meta ──
      final double? chartPrevClose = (meta?['chartPreviousClose'] as num?)?.toDouble() ??
          (meta?['previousClose'] as num?)?.toDouble();
      if (chartPrevClose != null && chartPrevClose > 0 && candles.isNotEmpty) {
        final lastDate = candles.last.timeStart;
        final prevDayCandles = candles.where((c) =>
          c.timeStart.isBefore(DateTime(lastDate.year, lastDate.month, lastDate.day))
        ).toList();
        if (prevDayCandles.isNotEmpty) {
          final lastPrevCandle = prevDayCandles.last;
          final idx = candles.indexOf(lastPrevCandle);
          if (idx != -1) {
            candles[idx] = lastPrevCandle.copyWith(
              close: chartPrevClose,
              high: chartPrevClose > lastPrevCandle.high ? chartPrevClose : lastPrevCandle.high,
              low: chartPrevClose < lastPrevCandle.low ? chartPrevClose : lastPrevCandle.low,
            );
          }
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
