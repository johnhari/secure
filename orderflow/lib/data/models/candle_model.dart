import '../../domain/entities/candle.dart';
import '../../core/utils/map_utils.dart';

class CandleModel extends Candle {
  const CandleModel({
    required super.symbol,
    required super.candleKey,
    required super.timeStart,
    required super.timeEnd,
    required super.open,
    required super.high,
    required super.low,
    required super.close,
    super.volume,
    super.buyerCount,
    super.sellerCount,
    super.isBigSignal,
    super.isMediumSignal,
    super.isTrap = false,
    super.isLiquidation = false,
    super.isInjected = false,
    super.injectedBy,
    super.isClosed = false,
    super.imbalances = const [],
    super.footprint = const {},
  });

  factory CandleModel.fromRTDB(Map<String, dynamic> json, String symbol) {
    return CandleModel(
      symbol: symbol,
      candleKey: json['candleKey'] as String,
      timeStart: DateTime.fromMillisecondsSinceEpoch(json['timeStart'] as int).toLocal(),
      timeEnd: DateTime.fromMillisecondsSinceEpoch(json['timeEnd'] as int).toLocal(),
      open: (json['open'] as num).toDouble(),
      high: (json['high'] as num).toDouble(),
      low: (json['low'] as num).toDouble(),
      close: (json['close'] as num).toDouble(),
      volume: json['volume'] as int? ?? 0,
      buyerCount: json['buyerCount'] as int?,
      sellerCount: json['sellerCount'] as int?,
      isBigSignal: json['isBigSignal'] as bool? ?? false,
      isMediumSignal: json['isMediumSignal'] as bool? ?? false,
      isTrap: json['isTrap'] as bool? ?? false,
      isLiquidation: json['isLiquidation'] as bool? ?? false,
      isInjected: json['isInjected'] as bool? ?? false,
      injectedBy: json['injectedBy'] as String?,
      isClosed: json['isClosed'] as bool? ?? false,
      imbalances: (json['imbalances'] as List<dynamic>?)
              ?.map((e) {
                final m = MapUtils.extractMap(e);
                return m != null ? PriceImbalanceModel.fromJson(m) : null;
              })
              .whereType<PriceImbalanceModel>()
              .toList() ??
          const [],
      footprint: _parseFootprint(json['footprint']),
    );
  }

  static Map<double, PriceLevelDataModel> _parseFootprint(dynamic raw) {
    final map = MapUtils.extractMap(raw);
    if (map == null || map.isEmpty) return const {};
    final Map<double, PriceLevelDataModel> result = {};
    map.forEach((k, v) {
      final double? price = double.tryParse(k.toString());
      final data = MapUtils.extractMap(v);
      if (price != null && data != null) {
        result[price] = PriceLevelDataModel.fromJson(data);
      }
    });
    return result;
  }

  factory CandleModel.fromJson(Map<String, dynamic> json) {
    return CandleModel(
      symbol: json['symbol'] as String,
      candleKey: json['candleKey'] as String,
      timeStart: DateTime.fromMillisecondsSinceEpoch(json['timeStart'] as int).toLocal(),
      timeEnd: DateTime.fromMillisecondsSinceEpoch(json['timeEnd'] as int).toLocal(),
      open: (json['open'] as num).toDouble(),
      high: (json['high'] as num).toDouble(),
      low: (json['low'] as num).toDouble(),
      close: (json['close'] as num).toDouble(),
      volume: json['volume'] as int? ?? 0,
      buyerCount: json['buyerCount'] as int?,
      sellerCount: json['sellerCount'] as int?,
      isBigSignal: json['isBigSignal'] as bool? ?? false,
      isMediumSignal: json['isMediumSignal'] as bool? ?? false,
      isTrap: json['isTrap'] as bool? ?? false,
      isLiquidation: json['isLiquidation'] as bool? ?? false,
      isInjected: json['isInjected'] as bool? ?? false,
      injectedBy: json['injectedBy'] as String?,
      isClosed: json['isClosed'] as bool? ?? false,
      imbalances: (json['imbalances'] as List<dynamic>?)
              ?.map((e) {
                final m = MapUtils.extractMap(e);
                return m != null ? PriceImbalanceModel.fromJson(m) : null;
              })
              .whereType<PriceImbalanceModel>()
              .toList() ??
          const [],
      footprint: _parseFootprint(json['footprint']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'symbol': symbol,
      'candleKey': candleKey,
      'timeStart': timeStart.millisecondsSinceEpoch,
      'timeEnd': timeEnd.millisecondsSinceEpoch,
      'open': open,
      'high': high,
      'low': low,
      'close': close,
      'volume': volume,
      'buyerCount': buyerCount,
      'sellerCount': sellerCount,
      'isBigSignal': isBigSignal,
      'isMediumSignal': isMediumSignal,
      'isTrap': isTrap,
      'isLiquidation': isLiquidation,
      'isInjected': isInjected,
      'injectedBy': injectedBy,
      'isClosed': isClosed,
      'imbalances': imbalances
          .map((e) => PriceImbalanceModel.fromEntity(e).toJson())
          .toList(),
      'footprint': footprint.map(
        (k, v) => MapEntry(k.toString(), PriceLevelDataModel.fromEntity(v).toJson()),
      ),
    };
  }

  Candle toEntity() {
    return Candle(
      symbol: symbol,
      candleKey: candleKey,
      timeStart: timeStart,
      timeEnd: timeEnd,
      open: open,
      high: high,
      low: low,
      close: close,
      volume: volume,
      buyerCount: buyerCount,
      sellerCount: sellerCount,
      isBigSignal: isBigSignal,
      isMediumSignal: isMediumSignal,
      isTrap: isTrap,
      isLiquidation: isLiquidation,
      isInjected: isInjected,
      injectedBy: injectedBy,
      imbalances: imbalances,
      footprint: footprint,
    );
  }

  factory CandleModel.fromEntity(Candle candle) {
    return CandleModel(
      symbol: candle.symbol,
      candleKey: candle.candleKey,
      timeStart: candle.timeStart,
      timeEnd: candle.timeEnd,
      open: candle.open,
      high: candle.high,
      low: candle.low,
      close: candle.close,
      volume: candle.volume,
      buyerCount: candle.buyerCount,
      sellerCount: candle.sellerCount,
      isBigSignal: candle.isBigSignal,
      isMediumSignal: candle.isMediumSignal,
      isTrap: candle.isTrap,
      isLiquidation: candle.isLiquidation,
      isInjected: candle.isInjected,
      injectedBy: candle.injectedBy,
      isClosed: candle.isClosed,
      imbalances: candle.imbalances,
      footprint: candle.footprint,
    );
  }

  @override
  CandleModel copyWith({
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
    return CandleModel(
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

class PriceImbalanceModel extends PriceImbalance {
  const PriceImbalanceModel({
    required super.price,
    required super.type,
    required super.size,
  });

  factory PriceImbalanceModel.fromJson(Map<String, dynamic> json) {
    return PriceImbalanceModel(
      price: (json['price'] as num).toDouble(),
      type: json['type'] as String,
      size: json['size'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'price': price,
      'type': type,
      'size': size,
    };
  }

  factory PriceImbalanceModel.fromEntity(PriceImbalance entity) {
    return PriceImbalanceModel(
      price: entity.price,
      type: entity.type,
      size: entity.size,
    );
  }
}

class PriceLevelDataModel extends PriceLevelData {
  const PriceLevelDataModel({
    required super.buyVolume,
    required super.sellVolume,
  });

  factory PriceLevelDataModel.fromJson(Map<String, dynamic> json) {
    return PriceLevelDataModel(
      buyVolume: json['buyVolume'] as int,
      sellVolume: json['sellVolume'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'buyVolume': buyVolume,
      'sellVolume': sellVolume,
    };
  }

  factory PriceLevelDataModel.fromEntity(PriceLevelData entity) {
    return PriceLevelDataModel(
      buyVolume: entity.buyVolume,
      sellVolume: entity.sellVolume,
    );
  }
}
