import 'package:firebase_database/firebase_database.dart';
import '../models/candle_model.dart';
import '../../core/utils/map_utils.dart';

class FirebaseMarketDataSource {
  final FirebaseDatabase _database;

  FirebaseMarketDataSource({FirebaseDatabase? database})
      : _database = database ?? FirebaseDatabase.instance;

  /// Fetch historical candles from Firebase RTDB (market_data/{symbol}/candles).
  /// Backward-compatible: handles old records that may lack timeStart/timeEnd fields.
  Future<List<CandleModel>> fetchHistoricalCandles(String symbol) async {
    try {
      final snapshot = await _database.ref('market_data/$symbol/candles').get();

      print('FirebaseMarketDataSource [$symbol]: exists=${snapshot.exists}, count=${snapshot.children.length}');

      if (!snapshot.exists) return [];

      final raw = MapUtils.extractMap(snapshot.value);
      if (raw == null) return [];
      final List<CandleModel> candles = [];

      raw.forEach((key, value) {
        final m = MapUtils.extractMap(value);
        if (m == null) return;
        try {
          // ── Backward-compat: old records may lack timeStart / timeEnd ──
          // The RTDB key is the 5-minute-aligned ms epoch; fall back to it.
          if (m['timeStart'] == null) {
            final ts = m['timestamp'] as int? ??
                (int.tryParse(key.toString()) ?? 0);
            m['timeStart'] = ts;
            m['timeEnd']   = ts + (5 * 60 * 1000);
          }
          // Ensure candleKey is always a non-null String
          m['candleKey'] ??= m['timeStart'].toString();

          candles.add(CandleModel.fromRTDB(m, symbol));
        } catch (e) {
          print('FirebaseMarketDataSource [$symbol]: skip candle $key — $e');
        }
      });

      candles.sort((a, b) => a.timeStart.compareTo(b.timeStart));
      print('FirebaseMarketDataSource [$symbol]: parsed ${candles.length} candles OK');
      return candles;
    } catch (e) {
      print('FirebaseMarketDataSource [$symbol]: Error — $e');
      return [];
    }
  }

  /// Listen to live candle updates from RTDB.
  Stream<CandleModel> getCandleStream(String symbol) {
    return _database
        .ref('market_data/$symbol/candles')
        .onChildChanged
        .map((event) {
      final raw = MapUtils.extractMap(event.snapshot.value) ?? <String, dynamic>{};
      if (raw['timeStart'] == null) {
        final ts = raw['timestamp'] as int? ?? 0;
        raw['timeStart'] = ts;
        raw['timeEnd']   = ts + (5 * 60 * 1000);
      }
      raw['candleKey'] ??= raw['timeStart'].toString();
      return CandleModel.fromRTDB(raw, symbol);
    });
  }

  /// Wipe all historical candles for a symbol.
  Future<void> wipeHistoricalCandles(String symbol) async {
    try {
      await _database.ref('market_data/$symbol/candles').remove();
      print('FirebaseMarketDataSource [$symbol]: candles wiped');
    } catch (e) {
      print('FirebaseMarketDataSource [$symbol]: Error wiping — $e');
      rethrow;
    }
  }

  /// Stream the Nifty 50 heatmap data from RTDB.
  Stream<Map<String, Map<String, dynamic>>> getHeatmapStream() {
    return _database.ref('market_data/nifty50_heatmap').onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) {
        return <String, Map<String, dynamic>>{};
      }
      try {
        final val = MapUtils.extractMap(event.snapshot.value);
        if (val == null) return <String, Map<String, dynamic>>{};
        final Map<String, Map<String, dynamic>> result = {};
        val.forEach((k, v) {
          final dataMap = MapUtils.extractMap(v);
          if (dataMap != null) {
            result[k.toString()] = dataMap;
          }
        });
        return result;
      } catch (e) {
        print('FirebaseMarketDataSource [Heatmap Stream Error]: $e');
        return <String, Map<String, dynamic>>{};
      }
    });
  }

  /// Stream the latest AI trade signal for an instrument from RTDB.
  Stream<Map<String, dynamic>?> getSignalStream(String instrument) {
    return _database.ref('trade_signals/$instrument/latest').onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) {
        return null;
      }
      try {
        return MapUtils.extractMap(event.snapshot.value);
      } catch (e) {
        print('FirebaseMarketDataSource [Signal Stream Error]: $e');
        return null;
      }
    });
  }

  /// Fetch signal history for an instrument from RTDB.
  Future<List<Map<String, dynamic>>> getSignalHistory(String instrument) async {
    try {
      final snapshot = await _database
          .ref('trade_signals/$instrument/history')
          .orderByKey()
          .limitToLast(20)
          .get();

      if (!snapshot.exists) return [];

      final raw = MapUtils.extractMap(snapshot.value);
      if (raw == null) return [];
      final List<Map<String, dynamic>> history = [];
      raw.forEach((key, value) {
        final m = MapUtils.extractMap(value);
        if (m != null) {
          history.add(m);
        }
      });

      // Sort descending by timestamp
      history.sort((a, b) =>
        ((b['timestamp'] as num?) ?? 0).compareTo((a['timestamp'] as num?) ?? 0));

      return history;
    } catch (e) {
      print('FirebaseMarketDataSource [Signal History Error]: $e');
      return [];
    }
  }
}

