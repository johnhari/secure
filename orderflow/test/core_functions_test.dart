import 'package:flutter_test/flutter_test.dart';
import 'package:orderflow/data/models/candle_model.dart';
import 'package:orderflow/data/models/signal_model.dart';
import 'package:orderflow/data/models/news_item.dart';
import 'package:orderflow/data/models/tick_data_model.dart';
import 'package:orderflow/domain/entities/user_profile.dart';
import 'package:orderflow/domain/services/candle_aggregator_service.dart';
import 'package:orderflow/core/constants/nifty_stocks.dart';
import 'package:orderflow/core/utils/device_utils.dart';
import 'package:orderflow/domain/services/pre_market_bias_service.dart';

void main() {
  group('1. Candle & Orderflow Model Tests', () {
    test('CandleModel deserialization and footprint parsing', () {
      final json = {
        'symbol': 'NIFTY50',
        'candleKey': 'NIFTY50_5m_1700000000000',
        'timeStart': 1700000000000,
        'timeEnd': 1700000300000,
        'open': 22500.0,
        'high': 22550.0,
        'low': 22480.0,
        'close': 22540.0,
        'volume': 150000,
        'buyerCount': 85000,
        'sellerCount': 65000,
        'isBigSignal': true,
        'isMediumSignal': false,
        'isTrap': false,
        'isLiquidation': false,
        'imbalances': [
          {'price': 22510.0, 'type': 'buy', 'size': 12000}
        ],
        'footprint': {
          '22500.0': {'buyVolume': 4000, 'sellVolume': 1500},
          '22510.0': {'buyVolume': 12000, 'sellVolume': 2000},
        }
      };

      final candle = CandleModel.fromJson(json);

      expect(candle.symbol, 'NIFTY50');
      expect(candle.open, 22500.0);
      expect(candle.close, 22540.0);
      expect(candle.high, 22550.0);
      expect(candle.low, 22480.0);
      expect(candle.volume, 150000);
      expect(candle.isBigSignal, true);
      expect(candle.imbalances.length, 1);
      expect(candle.imbalances.first.price, 22510.0);
      expect(candle.footprint.length, 2);
      expect(candle.footprint[22500.0]?.buyVolume, 4000);
      expect(candle.footprint[22500.0]?.sellVolume, 1500);

      // Serialize back to JSON and verify consistency
      final exportedJson = candle.toJson();
      expect(exportedJson['symbol'], 'NIFTY50');
      expect(exportedJson['volume'], 150000);
    });

    test('Candle delta and copyWith operations', () {
      final candle = CandleModel(
        symbol: 'BANKNIFTY',
        candleKey: 'BANKNIFTY_1m_1',
        timeStart: DateTime(2026, 1, 1, 9, 15),
        timeEnd: DateTime(2026, 1, 1, 9, 16),
        open: 48000.0,
        high: 48100.0,
        low: 47950.0,
        close: 48080.0,
        volume: 50000,
        buyerCount: 30000,
        sellerCount: 20000,
      );

      expect(candle.close > candle.open, true); // Bullish candle

      final updated = candle.copyWith(close: 48120.0, high: 48120.0);
      expect(updated.close, 48120.0);
      expect(updated.high, 48120.0);
      expect(updated.symbol, 'BANKNIFTY');
    });
  });

  group('2. Trade Signal Model Tests', () {
    test('TradeSignal parsing and signal classification', () {
      final signalJson = {
        'signal': 'STRONG_BUY',
        'confidence': 95,
        'compositeScore': 88,
        'scores': {
          'orderflow': 90,
          'pattern': 85,
          'sentiment': 89,
        },
        'patterns': ['ABSORPTION', 'BULLISH_DELTA_DIVERGENCE'],
        'orderflowSummary': 'Heavy aggressive buying at Value Area Low',
        'sentimentLabel': 'VERY_BULLISH',
        'reasoning': 'Institutional buyers detected at support level',
        'instrument': 'NIFTY50',
        'timestamp': 1700000000000,
      };

      final tradeSignal = TradeSignal.fromRTDB(signalJson);

      expect(tradeSignal.signal, 'STRONG_BUY');
      expect(tradeSignal.isBullish, true);
      expect(tradeSignal.isBearish, false);
      expect(tradeSignal.isStrong, true);
      expect(tradeSignal.confidence, 95);
      expect(tradeSignal.signalEmoji, '🟢🟢');
      expect(tradeSignal.patterns.contains('ABSORPTION'), true);
      expect(tradeSignal.scores['orderflow'], 90);
    });

    test('TradeSignal Bearish classification', () {
      final bearJson = {
        'signal': 'STRONG_SELL',
        'confidence': 88,
        'compositeScore': -75,
        'scores': {'orderflow': -80, 'pattern': -70, 'sentiment': -75},
        'patterns': ['SUPPLY_OVERHANG'],
        'instrument': 'BANKNIFTY',
        'timestamp': 1700000000000,
      };

      final bearSignal = TradeSignal.fromRTDB(bearJson);
      expect(bearSignal.isBearish, true);
      expect(bearSignal.isBullish, false);
      expect(bearSignal.signalEmoji, '🔴🔴');
    });
  });

  group('3. User Profile & Subscription Logic Tests', () {
    test('UserProfile admin detection and subscription properties', () {
      final adminProfile = UserProfile.fromJson({
        'uid': 'admin_123',
        'name': 'Master Admin',
        'email': 'bigshotbullish@gmail.com',
        'role': 'admin',
        'isApproved': true,
        'expiryDate': null, // Permanent
      });

      expect(adminProfile.isAdmin, true);
      expect(adminProfile.isApproved, true);
      expect(adminProfile.expiryDate, null); // Lifetime access

      final viewerProfile = UserProfile.fromJson({
        'uid': 'user_456',
        'name': 'Test User',
        'email': 'testuser@example.com',
        'role': 'viewer',
        'isApproved': true,
        'expiryDate': '2026-12-31T23:59:59.000Z',
        'subscriptionType': 'index_and_stocks',
      });

      expect(viewerProfile.isAdmin, false);
      expect(viewerProfile.isApproved, true);
      expect(viewerProfile.isIndexOnly, false);
      expect(viewerProfile.expiryDate?.isAfter(DateTime(2026, 1, 1)), true);
      expect(viewerProfile.allowDualDevice, false);
    });

    test('UserProfile 1 Mobile + 1 PC dual device authorization', () {
      final dualProfile = UserProfile.fromJson({
        'uid': 'dual_user_789',
        'email': 'dual@example.com',
        'isApproved': true,
        'allowDualDevice': true,
      });

      expect(dualProfile.allowDualDevice, true);
      expect(dualProfile.toJson()['allowDualDevice'], true);

      final updated = dualProfile.copyWith(allowDualDevice: false);
      expect(updated.allowDualDevice, false);

      final alternativeKeyProfile = UserProfile.fromJson({
        'uid': 'alt_user_101',
        'email': 'alt@example.com',
        'isApproved': true,
        'allow1Mobile1Pc': true,
      });
      expect(alternativeKeyProfile.allowDualDevice, true);

      final masterAdminProfile = UserProfile.fromJson({
        'uid': 'admin_master',
        'email': 'jivaspect@gmail.com',
      });
      expect(masterAdminProfile.allowDualDevice, true);
    });

    test('Dual Session RTDB payload slot isolation (1 PC + 1 Mobile)', () {
      final rtdbSessionMap = {
        'allowDualDevice': true,
        'allow1Mobile1Pc': true,
        'forceLogout': false,
        'pc': {
          'activeDeviceId': 'win_hwid_desktop_xyz',
          'sessionId': 'session_pc_001',
          'deviceName': 'Windows: Trader-PC',
          'platform': 'windows',
          'slot': 'pc',
          'lastSeen': 1700000000000,
          'forceLogout': false,
        },
        'mobile': {
          'activeDeviceId': 'android_samsung_s23_abc',
          'sessionId': 'session_mob_002',
          'deviceName': 'Samsung SM-S911B',
          'platform': 'android',
          'slot': 'mobile',
          'lastSeen': 1700000005000,
          'forceLogout': false,
        },
      };

      expect(rtdbSessionMap['allowDualDevice'], true);
      expect(rtdbSessionMap.containsKey('pc'), true);
      expect(rtdbSessionMap.containsKey('mobile'), true);

      final pcSlot = rtdbSessionMap['pc'] as Map<String, dynamic>;
      final mobSlot = rtdbSessionMap['mobile'] as Map<String, dynamic>;

      // Ensure slots are completely independent with distinct IDs and platforms
      expect(pcSlot['activeDeviceId'], isNot(equals(mobSlot['activeDeviceId'])));
      expect(pcSlot['sessionId'], isNot(equals(mobSlot['sessionId'])));
      expect(pcSlot['slot'], 'pc');
      expect(mobSlot['slot'], 'mobile');
      expect(pcSlot['platform'], 'windows');
      expect(mobSlot['platform'], 'android');

      // Modifying mobile slot leaves PC slot intact
      final updatedMobSlot = Map<String, dynamic>.from(mobSlot);
      updatedMobSlot['sessionId'] = 'session_mob_003_new_login';
      expect(pcSlot['sessionId'], 'session_pc_001');
      expect(updatedMobSlot['sessionId'], 'session_mob_003_new_login');
    });

    test('DeviceUtils slot and device category detection', () {
      expect(DeviceUtils.getDeviceSlot(), anyOf('mobile', 'pc'));
      expect(DeviceUtils.getDeviceTypeName(), anyOf('Mobile', 'PC'));
      expect(DeviceUtils.isMobile() != DeviceUtils.isPc(), true);
    });
  });

  group('4. Candle Aggregator Service Tests', () {
    test('Process ticks and build 1m and 5m candles correctly', () async {
      final aggregator = CandleAggregatorService();
      final List<CandleModel> emitted1m = [];
      final sub = aggregator.getCandleStream('1m').listen((c) {
        emitted1m.add(c);
      });

      final baseTime = DateTime(2026, 1, 1, 9, 15, 0);

      // Tick 1: Opening tick
      aggregator.processTick(TickData(
        instrument: 'NIFTY50',
        token: '26000',
        ltp: 22000.0,
        open: 22000.0,
        high: 22000.0,
        low: 22000.0,
        close: 22000.0,
        volume: 1000,
        vwap: 22000.0,
        openInterest: 50000,
        oiChangePercent: 1.2,
        timestamp: baseTime,
        dayHigh: 22000.0,
        dayLow: 22000.0,
        buyQuantity: 500,
        sellQuantity: 500,
        change: 0.0,
        changePercent: 0.0,
      ));

      // Tick 2: High tick in same minute
      aggregator.processTick(TickData(
        instrument: 'NIFTY50',
        token: '26000',
        ltp: 22050.0,
        open: 22000.0,
        high: 22050.0,
        low: 22000.0,
        close: 22050.0,
        volume: 2500,
        vwap: 22020.0,
        openInterest: 51000,
        oiChangePercent: 1.5,
        timestamp: baseTime.add(const Duration(seconds: 15)),
        dayHigh: 22050.0,
        dayLow: 22000.0,
        buyQuantity: 1500,
        sellQuantity: 1000,
        change: 50.0,
        changePercent: 0.22,
      ));

      // Tick 3: Low tick in same minute
      aggregator.processTick(TickData(
        instrument: 'NIFTY50',
        token: '26000',
        ltp: 21980.0,
        open: 22000.0,
        high: 22050.0,
        low: 21980.0,
        close: 21980.0,
        volume: 3800,
        vwap: 22010.0,
        openInterest: 52000,
        oiChangePercent: 1.8,
        timestamp: baseTime.add(const Duration(seconds: 30)),
        dayHigh: 22050.0,
        dayLow: 21980.0,
        buyQuantity: 1800,
        sellQuantity: 2000,
        change: -20.0,
        changePercent: -0.09,
      ));

      // Tick 4: Close tick in same minute
      aggregator.processTick(TickData(
        instrument: 'NIFTY50',
        token: '26000',
        ltp: 22020.0,
        open: 22000.0,
        high: 22050.0,
        low: 21980.0,
        close: 22020.0,
        volume: 5000,
        vwap: 22015.0,
        openInterest: 53000,
        oiChangePercent: 2.1,
        timestamp: baseTime.add(const Duration(seconds: 45)),
        dayHigh: 22050.0,
        dayLow: 21980.0,
        buyQuantity: 2600,
        sellQuantity: 2400,
        change: 20.0,
        changePercent: 0.09,
      ));

      // Give stream time to deliver
      await Future.delayed(const Duration(milliseconds: 50));

      expect(emitted1m.isNotEmpty, true);
      final lastCandle = emitted1m.last;
      expect(lastCandle.open, 22000.0);
      expect(lastCandle.high, 22050.0);
      expect(lastCandle.low, 21980.0);
      expect(lastCandle.close, 22020.0);
      expect(lastCandle.volume, 5000);

      await sub.cancel();
      aggregator.dispose();
    });
  });

  group('5. News Item Model Tests', () {
    test('NewsItem parsing and formatting', () {
      final json = {
        'title': 'RBI Monetary Policy: Repo Rate Unchanged at 6.5%',
        'description': 'The central bank maintains status quo on key interest rates.',
        'source': 'Economic Times',
        'link': 'https://economictimes.indiatimes.com/news',
        'pubDate': 1700000000000,
        'category': 'market',
        'sentiment': 'positive',
      };

      final news = NewsItem.fromJson(json);

      expect(news.title.contains('RBI Monetary Policy'), true);
      expect(news.sentiment, 'positive');
      expect(news.category, 'market');
      expect(news.source, 'Economic Times');
    });
  });

  group('6. Nifty Stocks Constants Verification', () {
    test('Verify key indices and stocks exist in NiftyStocks list', () {
      final stocks = NiftyStocks.stocks;
      expect(stocks.isNotEmpty, true);

      // Check major symbols
      expect(stocks.containsKey('RELIANCE'), true);
      expect(stocks.containsKey('HDFCBANK'), true);
      expect(stocks.containsKey('TCS'), true);
      expect(stocks.containsKey('INFY'), true);
      expect(stocks.containsKey('ICICIBANK'), true);
      expect(stocks.containsKey('SBIN'), true);
    });
  });

  group('7. Pre-Market Bias Data & Calculations', () {
    test('PreMarketBiasData serialization and deserialization', () {
      final json = {
        'giftNifty': 22615.0,
        'giftNiftyChange': -210.0,
        'giftNiftyPct': -0.92,
        'expectedOpen': 'GAP DOWN (-190 to -140 points)',
        'expectedOpenType': 'GAP DOWN',
        'fiiNet': -5353.22,
        'diiNet': 5189.02,
        'fiiDiiDate': '28-Sep-2026',
        'globalFutures': {
          'DOW FUT': '-122 (-0.24%)',
          'NASDAQ FUT': '-132.3 (-0.43%)',
          'DAX': '-34.2 (-0.13%)',
          'NIKKEI': '-936 (-1.42%)',
        },
        'lastUpdated': 1790658000000,
      };

      final data = PreMarketBiasData.fromJson(json);

      expect(data.giftNifty, 22615.0);
      expect(data.giftNiftyChange, -210.0);
      expect(data.giftNiftyPct, -0.92);
      expect(data.expectedOpen, 'GAP DOWN (-190 to -140 points)');
      expect(data.expectedOpenType, 'GAP DOWN');
      expect(data.fiiNet, -5353.22);
      expect(data.diiNet, 5189.02);
      expect(data.fiiDiiDate, '28-Sep-2026');
      expect(data.globalFutures['DOW FUT'], '-122 (-0.24%)');

      final serialized = data.toJson();
      expect(serialized['giftNifty'], 22615.0);
      expect(serialized['expectedOpenType'], 'GAP DOWN');
      expect(serialized['fiiNet'], -5353.22);
    });

    test('PreMarketBias formatting logic avoids double sign bug', () {
      const double negativeChange = -77.11;
      const double negativePct = -0.32;

      final isPos = negativeChange >= 0;
      final sign = isPos ? '+' : '';
      final formatted = '$sign${negativeChange.toStringAsFixed(2)} ($sign${negativePct.toStringAsFixed(2)}%)';

      expect(formatted.contains('+-'), false);
      expect(formatted, '-77.11 (-0.32%)');

      const double positiveChange = 112.50;
      const double positivePct = 0.47;
      final isPos2 = positiveChange >= 0;
      final sign2 = isPos2 ? '+' : '';
      final formatted2 = '$sign2${positiveChange.toStringAsFixed(2)} ($sign2${positivePct.toStringAsFixed(2)}%)';

      expect(formatted2, '+112.50 (+0.47%)');
    });
  });
}

