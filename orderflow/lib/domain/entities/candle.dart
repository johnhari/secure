import 'package:equatable/equatable.dart';

class Candle extends Equatable {
  final String symbol;
  final String candleKey;
  final DateTime timeStart;
  final DateTime timeEnd;
  final double open;
  final double high;
  final double low;
  final double close;
  final int volume;
  final int? buyerCount;
  final int? sellerCount;
  final bool isBigSignal;
  final bool isMediumSignal;
  final bool isTrap;
  final bool isLiquidation;
  final bool isInjected;
  final String? injectedBy;
  final bool isClosed;
  final List<PriceImbalance> imbalances;
  final Map<double, PriceLevelData> footprint;

  const Candle({
    required this.symbol,
    required this.candleKey,
    required this.timeStart,
    required this.timeEnd,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume = 0,
    this.buyerCount,
    this.sellerCount,
    this.isBigSignal = false,
    this.isMediumSignal = false,
    this.isTrap = false,
    this.isLiquidation = false,
    this.isInjected = false,
    this.injectedBy,
    this.isClosed = false,
    this.imbalances = const [],
    this.footprint = const {},
  });

  bool get isBullish => close >= open;
  bool get isBearish => close < open;
  bool get hasOrderflowData => buyerCount != null && sellerCount != null;

  int get delta => (buyerCount ?? 0) - (sellerCount ?? 0);
  bool get hasImbalances => imbalances.isNotEmpty;

  int get simulatedCount {
    final range = (high - low).abs();
    final random = (candleKey.hashCode % 1000) / 1000.0;
    
    if (range < 20) {
      return 1000 + (random * 2000).toInt(); // 1k to 3k
    } else if (range >= 30 && range <= 40) {
      return 4000 + (random * 4000).toInt(); // 4k to 8k
    } else if (range > 70) {
      return 12000 + (random * 8000).toInt(); // 12k to 20k
    } else {
      // Default variety between 2k and 15k
      return 2000 + (candleKey.hashCode % 13001);
    }
  }

  @override
  List<Object?> get props => [
        symbol,
        candleKey,
        timeStart,
        timeEnd,
        open,
        high,
        low,
        close,
        volume,
        buyerCount,
        sellerCount,
        isBigSignal,
        isMediumSignal,
        isTrap,
        isLiquidation,
        isInjected,
        injectedBy,
        isClosed,
        imbalances,
        footprint,
      ];

  Candle copyWith({
    String? symbol,
    String? candleKey,
    DateTime? timeStart,
    DateTime? timeEnd,
    double? open,
    double? high,
    double? low,
    double? close,
    int? volume,
    int? buyerCount,
    int? sellerCount,
    bool? isBigSignal,
    bool? isMediumSignal,
    bool? isTrap,
    bool? isLiquidation,
    bool? isInjected,
    String? injectedBy,
    bool? isClosed,
    List<PriceImbalance>? imbalances,
    Map<double, PriceLevelData>? footprint,
  }) {
    return Candle(
      symbol: symbol ?? this.symbol,
      candleKey: candleKey ?? this.candleKey,
      timeStart: timeStart ?? this.timeStart,
      timeEnd: timeEnd ?? this.timeEnd,
      open: open ?? this.open,
      high: high ?? this.high,
      low: low ?? this.low,
      close: close ?? this.close,
      volume: volume ?? this.volume,
      buyerCount: buyerCount ?? this.buyerCount,
      sellerCount: sellerCount ?? this.sellerCount,
      isBigSignal: isBigSignal ?? this.isBigSignal,
      isMediumSignal: isMediumSignal ?? this.isMediumSignal,
      isTrap: isTrap ?? this.isTrap,
      isLiquidation: isLiquidation ?? this.isLiquidation,
      isInjected: isInjected ?? this.isInjected,
      injectedBy: injectedBy ?? this.injectedBy,
      isClosed: isClosed ?? this.isClosed,
      imbalances: imbalances ?? this.imbalances,
      footprint: footprint ?? this.footprint,
    );
  }
}

class PriceImbalance extends Equatable {
  final double price;
  final String type; // 'buy' or 'sell'
  final int size;

  const PriceImbalance({
    required this.price,
    required this.type,
    required this.size,
  });

  @override
  List<Object?> get props => [price, type, size];
}

class PriceLevelData extends Equatable {
  final int buyVolume;
  final int sellVolume;

  const PriceLevelData({
    required this.buyVolume,
    required this.sellVolume,
  });

  int get totalVolume => buyVolume + sellVolume;
  int get delta => buyVolume - sellVolume;

  @override
  List<Object?> get props => [buyVolume, sellVolume];
}
