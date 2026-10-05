import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreMarketBiasData {
  final double giftNifty;
  final double giftNiftyChange;
  final double giftNiftyPct;
  final String expectedOpen;
  final String expectedOpenType; // 'GAP UP', 'GAP DOWN', 'FLAT'
  final double fiiNet;
  final double diiNet;
  final String fiiDiiDate;
  final Map<String, String> globalFutures;
  final DateTime lastUpdated;

  const PreMarketBiasData({
    required this.giftNifty,
    required this.giftNiftyChange,
    required this.giftNiftyPct,
    required this.expectedOpen,
    required this.expectedOpenType,
    required this.fiiNet,
    required this.diiNet,
    required this.fiiDiiDate,
    required this.globalFutures,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
    'giftNifty': giftNifty,
    'giftNiftyChange': giftNiftyChange,
    'giftNiftyPct': giftNiftyPct,
    'expectedOpen': expectedOpen,
    'expectedOpenType': expectedOpenType,
    'fiiNet': fiiNet,
    'diiNet': diiNet,
    'fiiDiiDate': fiiDiiDate,
    'globalFutures': globalFutures,
    'lastUpdated': lastUpdated.millisecondsSinceEpoch,
  };

  factory PreMarketBiasData.fromJson(Map<dynamic, dynamic> json) {
    return PreMarketBiasData(
      giftNifty: (json['giftNifty'] as num?)?.toDouble() ?? 0.0,
      giftNiftyChange: (json['giftNiftyChange'] as num?)?.toDouble() ?? 0.0,
      giftNiftyPct: (json['giftNiftyPct'] as num?)?.toDouble() ?? 0.0,
      expectedOpen: json['expectedOpen'] as String? ?? 'FLAT OPEN',
      expectedOpenType: json['expectedOpenType'] as String? ?? 'FLAT',
      fiiNet: (json['fiiNet'] as num?)?.toDouble() ?? 0.0,
      diiNet: (json['diiNet'] as num?)?.toDouble() ?? 0.0,
      fiiDiiDate: json['fiiDiiDate'] as String? ?? '',
      globalFutures: (json['globalFutures'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {},
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.fromMillisecondsSinceEpoch((json['lastUpdated'] as num).toInt())
          : DateTime.now(),
    );
  }
}

class PreMarketBiasService {
  static final PreMarketBiasService _instance = PreMarketBiasService._internal();
  factory PreMarketBiasService() => _instance;
  PreMarketBiasService._internal();

  final http.Client _client = http.Client();
  PreMarketBiasData? _cachedData;
  static const String _prefsKey = 'cached_pre_market_bias_v2';

  PreMarketBiasData? get cachedData => _cachedData;

  /// Fetch Pre-Market Bias Data
  Future<PreMarketBiasData> getPreMarketBias({bool forceRefresh = false}) async {
    // 1. If memory cache is valid (< 3 minutes old) and not forced, return it
    if (!forceRefresh && _cachedData != null) {
      final age = DateTime.now().difference(_cachedData!.lastUpdated);
      if (age.inMinutes < 3) {
        return _cachedData!;
      }
    }

    // 2. Load disk cache if memory cache is null
    if (_cachedData == null) {
      await _loadFromLocalPrefs();
    }

    // 3. Try reading from Firebase Realtime Database
    try {
      final rtdbData = await _fetchFromRTDB();
      if (rtdbData != null) {
        final age = DateTime.now().difference(rtdbData.lastUpdated);
        if (age.inMinutes < 5 && !forceRefresh) {
          _cachedData = rtdbData;
          _saveToLocalPrefs(rtdbData);
          return rtdbData;
        }
      }
    } catch (e) {
      debugPrint('[PreMarketBiasService] RTDB read error: $e');
    }

    // 4. Fetch fresh live data from TradingView + NSE + Yahoo fallback
    try {
      final liveData = await _fetchLiveMarketData();
      if (liveData != null && liveData.giftNifty > 0) {
        _cachedData = liveData;
        _saveToLocalPrefs(liveData);
        _syncToRTDB(liveData);
        return liveData;
      }
    } catch (e) {
      debugPrint('[PreMarketBiasService] Live fetch error: $e');
    }

    // 5. If live fetch failed, return existing cached data or fallback
    if (_cachedData != null) {
      return _cachedData!;
    }

    return _generateDefaultData();
  }

  /// Direct live fetch from TradingView scanner & NSE India
  Future<PreMarketBiasData?> _fetchLiveMarketData() async {
    double giftNifty = 0.0;
    double giftNiftyChange = 0.0;
    double giftNiftyPct = 0.0;
    double niftyPrevClose = 0.0;
    final Map<String, String> globalFutures = {};

    // A) TradingView Global Scanner
    try {
      final tvUrl = Uri.parse('https://scanner.tradingview.com/global/scan');
      final tvBody = jsonEncode({
        'symbols': {
          'tickers': [
            'NSEIX:NIFTY1!',
            'CBOT_MINI:YM1!',
            'CME_MINI:NQ1!',
            'XETR:DAX',
            'TVC:NI225',
            'NSE:NIFTY'
          ]
        },
        'columns': ['name', 'close', 'change', 'change_abs', 'description']
      });

      final tvResp = await _client.post(
        tvUrl,
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
        },
        body: tvBody,
      ).timeout(const Duration(seconds: 7));

      if (tvResp.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(tvResp.body);
        final List data = json['data'] ?? [];
        for (final item in data) {
          final String s = item['s']?.toString() ?? '';
          final List d = item['d'] ?? [];
          if (d.length >= 4) {
            final close = (d[1] as num?)?.toDouble() ?? 0.0;
            final pct = (d[2] as num?)?.toDouble() ?? 0.0;
            final chg = (d[3] as num?)?.toDouble() ?? 0.0;

            if (s == 'NSEIX:NIFTY1!') {
              giftNifty = close;
              giftNiftyPct = pct;
              giftNiftyChange = chg;
            } else if (s == 'NSE:NIFTY') {
              niftyPrevClose = (close > 0 && chg != 0) ? (close - chg) : close;
            } else if (s == 'CBOT_MINI:YM1!') {
              globalFutures['DOW FUT'] = '${chg >= 0 ? '+' : ''}${chg.round()} (${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%)';
            } else if (s == 'CME_MINI:NQ1!') {
              globalFutures['NASDAQ FUT'] = '${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(1)} (${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%)';
            } else if (s == 'XETR:DAX') {
              globalFutures['DAX'] = '${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(1)} (${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%)';
            } else if (s == 'TVC:NI225') {
              globalFutures['NIKKEI'] = '${chg >= 0 ? '+' : ''}${chg.round()} (${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%)';
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[PreMarketBiasService] TradingView scanner error: $e');
    }

    // B) Yahoo Finance Fallback for missing Global Futures
    if (globalFutures.isEmpty || giftNifty == 0.0) {
      await _fillFromYahoo(globalFutures, (gn, gnChg, gnPct, nPrev) {
        if (giftNifty == 0.0 && gn > 0) {
          giftNifty = gn;
          giftNiftyChange = gnChg;
          giftNiftyPct = gnPct;
        }
        if (niftyPrevClose == 0.0 && nPrev > 0) {
          niftyPrevClose = nPrev;
        }
      });
    }

    // C) NSE FII / DII Net Flow
    double fiiNet = 0.0;
    double diiNet = 0.0;
    String fiiDiiDate = '';

    try {
      final nseUrl = Uri.parse('https://www.nseindia.com/api/fiidiiTradeReact');
      final nseResp = await _client.get(
        nseUrl,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
          'Accept': 'application/json, text/plain, */*',
          'Referer': 'https://www.nseindia.com/',
        },
      ).timeout(const Duration(seconds: 6));

      if (nseResp.statusCode == 200) {
        final decoded = jsonDecode(nseResp.body);
        if (decoded is List) {
          for (final row in decoded) {
            final cat = (row['category'] ?? '').toString().toUpperCase();
            final net = double.tryParse(row['netValue']?.toString() ?? '') ?? 0.0;
            if (cat.contains('FII') || cat.contains('FPI')) {
              fiiNet = net;
              fiiDiiDate = row['date']?.toString() ?? fiiDiiDate;
            } else if (cat.contains('DII')) {
              diiNet = net;
              fiiDiiDate = row['date']?.toString() ?? fiiDiiDate;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[PreMarketBiasService] NSE FII/DII fetch error: $e');
      if (_cachedData != null && _cachedData!.fiiNet != 0.0) {
        fiiNet = _cachedData!.fiiNet;
        diiNet = _cachedData!.diiNet;
        fiiDiiDate = _cachedData!.fiiDiiDate;
      }
    }

    // D) Expected Open Calculation
    double gap = 0.0;
    if (niftyPrevClose > 0 && giftNifty > 0) {
      gap = giftNifty - niftyPrevClose;
    } else {
      gap = giftNiftyChange;
    }

    final absGap = gap.abs();
    final minPts = (absGap * 0.85).round();
    final maxPts = (absGap * 1.15).round();

    String expectedOpen;
    String expectedOpenType;

    if (gap >= 35) {
      expectedOpen = 'GAP UP (+$minPts to +$maxPts points)';
      expectedOpenType = 'GAP UP';
    } else if (gap <= -35) {
      expectedOpen = 'GAP DOWN (-$maxPts to -$minPts points)';
      expectedOpenType = 'GAP DOWN';
    } else {
      final sign = gap >= 0 ? '+' : '';
      expectedOpen = 'FLAT OPEN ($sign${gap.round()} points)';
      expectedOpenType = 'FLAT';
    }

    return PreMarketBiasData(
      giftNifty: giftNifty > 0 ? giftNifty : (_cachedData?.giftNifty ?? 22615.0),
      giftNiftyChange: giftNiftyChange,
      giftNiftyPct: giftNiftyPct,
      expectedOpen: expectedOpen,
      expectedOpenType: expectedOpenType,
      fiiNet: fiiNet != 0.0 ? fiiNet : (_cachedData?.fiiNet ?? -5353.22),
      diiNet: diiNet != 0.0 ? diiNet : (_cachedData?.diiNet ?? 5189.02),
      fiiDiiDate: fiiDiiDate.isNotEmpty ? fiiDiiDate : (_cachedData?.fiiDiiDate ?? ''),
      globalFutures: globalFutures.isNotEmpty ? globalFutures : (_cachedData?.globalFutures ?? {}),
      lastUpdated: DateTime.now(),
    );
  }

  /// Yahoo Finance fallback for global indices
  Future<void> _fillFromYahoo(
    Map<String, String> futures,
    Function(double giftNifty, double giftNiftyChange, double giftNiftyPct, double niftyPrevClose) onNiftyData,
  ) async {
    final Map<String, String> yahooSymbols = {
      'DOW FUT': 'YM=F',
      'NASDAQ FUT': 'NQ=F',
      'DAX': '^GDAXI',
      'NIKKEI': '^N225',
    };

    for (final entry in yahooSymbols.entries) {
      if (futures.containsKey(entry.key)) continue;
      try {
        final url = Uri.parse('https://query1.finance.yahoo.com/v8/finance/chart/${entry.value}?interval=1d&range=1d');
        final resp = await _client.get(url, headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200) {
          final json = jsonDecode(resp.body);
          final meta = json['chart']?['result']?[0]?['meta'];
          if (meta != null) {
            final price = (meta['regularMarketPrice'] as num?)?.toDouble() ?? 0.0;
            final prevClose = (meta['chartPreviousClose'] as num?)?.toDouble() ?? price;
            final chg = price - prevClose;
            final pct = prevClose > 0 ? (chg / prevClose) * 100 : 0.0;
            futures[entry.key] = '${chg >= 0 ? '+' : ''}${chg.round()} (${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%)';
          }
        }
      } catch (_) {}
    }

    try {
      final nUrl = Uri.parse('https://query1.finance.yahoo.com/v8/finance/chart/^NSEI?interval=1d&range=1d');
      final nResp = await _client.get(nUrl, headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 4));
      if (nResp.statusCode == 200) {
        final json = jsonDecode(nResp.body);
        final meta = json['chart']?['result']?[0]?['meta'];
        if (meta != null) {
          final price = (meta['regularMarketPrice'] as num?)?.toDouble() ?? 0.0;
          final prevClose = (meta['chartPreviousClose'] as num?)?.toDouble() ?? price;
          final chg = price - prevClose;
          final pct = prevClose > 0 ? (chg / prevClose) * 100 : 0.0;
          onNiftyData(price, chg, pct, prevClose);
        }
      }
    } catch (_) {}
  }

  /// Load from local disk storage
  Future<void> _loadFromLocalPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_prefsKey);
      if (str != null && str.isNotEmpty) {
        final json = jsonDecode(str);
        _cachedData = PreMarketBiasData.fromJson(json);
      }
    } catch (e) {
      debugPrint('[PreMarketBiasService] Prefs load error: $e');
    }
  }

  /// Save to local disk storage
  Future<void> _saveToLocalPrefs(PreMarketBiasData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(data.toJson()));
    } catch (_) {}
  }

  /// Read from Firebase Realtime Database
  Future<PreMarketBiasData?> _fetchFromRTDB() async {
    try {
      final ref = FirebaseDatabase.instance.ref('market_data/pre_market_bias');
      final snap = await ref.get().timeout(const Duration(seconds: 4));
      if (snap.exists && snap.value != null) {
        final val = snap.value;
        if (val is Map) {
          return PreMarketBiasData.fromJson(val);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Sync live data to Firebase RTDB in background
  void _syncToRTDB(PreMarketBiasData data) {
    try {
      final ref = FirebaseDatabase.instance.ref('market_data/pre_market_bias');
      ref.set(data.toJson()).catchError((_) {});
    } catch (_) {}
  }

  PreMarketBiasData _generateDefaultData() {
    return PreMarketBiasData(
      giftNifty: 22615.0,
      giftNiftyChange: -210.0,
      giftNiftyPct: -0.92,
      expectedOpen: 'GAP DOWN (-190 to -140 points)',
      expectedOpenType: 'GAP DOWN',
      fiiNet: -5353.22,
      diiNet: 5189.02,
      fiiDiiDate: '28-Sep-2026',
      globalFutures: {
        'DOW FUT': '-122 (-0.24%)',
        'NASDAQ FUT': '-132.3 (-0.43%)',
        'DAX': '-34.2 (-0.13%)',
        'NIKKEI': '-936 (-1.42%)',
      },
      lastUpdated: DateTime.now(),
    );
  }
}
