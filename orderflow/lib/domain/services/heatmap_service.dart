import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_database/firebase_database.dart';
import '../../core/constants/nifty_stocks.dart';

class HeatmapService {
  static final HeatmapService _instance = HeatmapService._internal();
  factory HeatmapService() => _instance;
  HeatmapService._internal();

  final http.Client _client = http.Client();
  DateTime? _lastFetchTime;
  Map<String, Map<String, dynamic>>? _cachedData;

  Map<String, Map<String, dynamic>>? get cachedData => _cachedData;
  DateTime? get lastFetchTime => _lastFetchTime;

  static const List<String> nifty50Symbols = [
    'ADANIENT', 'ADANIPORTS', 'APOLLOHOSP', 'ASIANPAINT', 'AXISBANK',
    'BAJAJ-AUTO', 'BAJFINANCE', 'BAJAJFINSV', 'BPCL', 'BHARTIARTL',
    'BRITANNIA', 'CIPLA', 'COALINDIA', 'DIVISLAB', 'DRREDDY',
    'EICHERMOT', 'GRASIM', 'HCLTECH', 'HDFCBANK', 'HDFCLIFE',
    'HEROMOTOCO', 'HINDALCO', 'HINDUNILVR', 'ICICIBANK', 'ITC',
    'INDUSINDBK', 'INFY', 'JSWSTEEL', 'KOTAKBANK', 'LTIM',
    'LT', 'M&M', 'MARUTI', 'NTPC', 'NESTLEIND',
    'ONGC', 'POWERGRID', 'RELIANCE', 'SBILIFE', 'SBIN',
    'SHRIRAMFIN', 'SUNPHARMA', 'TCS', 'TATACONSUM', 'TATAMOTORS',
    'TATASTEEL', 'TECHM', 'TITAN', 'ULTRACEMCO', 'WIPRO'
  ];

  static String toTvTicker(String s) {
    if (s == 'BAJAJ-AUTO') return 'NSE:BAJAJ_AUTO';
    if (s == 'M&M') return 'NSE:M&M';
    if (s == 'TATAMOTORS') return 'NSE:TMCV';
    return 'NSE:$s';
  }

  /// Fetch live data for all Nifty 50 stocks with points & percent
  Future<Map<String, Map<String, dynamic>>> fetchLiveHeatmapData({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh && _cachedData != null && _lastFetchTime != null) {
      if (now.difference(_lastFetchTime!).inSeconds < 10) {
        return _cachedData!;
      }
    }

    final tvTickers = nifty50Symbols.map(toTvTicker).toList();
    final Map<String, Map<String, dynamic>> heatmap = {};

    try {
      final url = Uri.parse('https://scanner.tradingview.com/india/scan');
      final resp = await _client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
        },
        body: jsonEncode({
          'symbols': {'tickers': tvTickers},
          'columns': ['name', 'close', 'change', 'change_abs', 'open', 'high', 'low', 'volume', 'description']
        }),
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(resp.body);
        final List data = json['data'] ?? [];

        final Map<String, List> lookup = {};
        for (final item in data) {
          final String s = item['s']?.toString() ?? '';
          lookup[s] = item['d'] as List;
        }

        for (final s in nifty50Symbols) {
          final tvSym = toTvTicker(s);
          if (lookup.containsKey(tvSym)) {
            final d = lookup[tvSym]!;
            final price = (d[1] as num?)?.toDouble() ?? 0.0;
            final changePct = (d[2] as num?)?.toDouble() ?? 0.0;
            final changePts = (d[3] as num?)?.toDouble() ?? 0.0;
            final open = (d[4] as num?)?.toDouble() ?? 0.0;
            final high = (d[5] as num?)?.toDouble() ?? 0.0;
            final low = (d[6] as num?)?.toDouble() ?? 0.0;
            final vol = (d[7] as num?)?.toInt() ?? 0;
            final name = d[8]?.toString() ?? NiftyStocks.stocks[s] ?? s;

            heatmap[s] = {
              'symbol': s,
              'name': name,
              'price': price,
              'change': changePts, // Points change!
              'changePercent': changePct,
              'open': open,
              'high': high,
              'low': low,
              'volume': vol,
              'lastUpdate': DateTime.now().millisecondsSinceEpoch,
            };
          }
        }
      }
    } catch (e) {
      debugPrint('[HeatmapService] TradingView scanner fetch error: $e');
    }

    // Fill missing LTIM or others from Yahoo if needed
    for (final s in nifty50Symbols) {
      if (!heatmap.containsKey(s) && _cachedData != null && _cachedData!.containsKey(s)) {
        heatmap[s] = _cachedData![s]!;
      }
    }

    if (heatmap.isNotEmpty) {
      _cachedData = heatmap;
      _lastFetchTime = DateTime.now();

      // Sync to Firebase RTDB in background
      _syncToRTDB(heatmap);
      return heatmap;
    }

    return _cachedData ?? {};
  }

  void _syncToRTDB(Map<String, Map<String, dynamic>> data) {
    try {
      final ref = FirebaseDatabase.instance.ref('market_data/nifty50_heatmap');
      ref.update(data).catchError((_) {});
    } catch (_) {}
  }
}
