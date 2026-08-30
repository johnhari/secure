class TickData {
  final String instrument;
  final String token;
  final double ltp;
  final double open;
  final double high;
  final double low;
  final double close;
  final int volume;
  final double vwap;
  final int openInterest;
  final double oiChangePercent;
  final DateTime timestamp;
  final double dayHigh;
  final double dayLow;
  final int buyQuantity;
  final int sellQuantity;
  final double change;
  final double changePercent;

  TickData({
    required this.instrument,
    required this.token,
    required this.ltp,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.vwap,
    required this.openInterest,
    required this.oiChangePercent,
    required this.timestamp,
    required this.dayHigh,
    required this.dayLow,
    required this.buyQuantity,
    required this.sellQuantity,
    required this.change,
    required this.changePercent,
  });

  factory TickData.fromJson(Map<String, dynamic> json) {
    return TickData(
      instrument: json['instrument'] ?? '',
      token: json['token'] ?? '',
      ltp: (json['ltp'] ?? 0.0).toDouble(),
      open: (json['open'] ?? 0.0).toDouble(),
      high: (json['high'] ?? 0.0).toDouble(),
      low: (json['low'] ?? 0.0).toDouble(),
      close: (json['close'] ?? 0.0).toDouble(),
      volume: json['volume'] ?? 0,
      vwap: (json['vwap'] ?? 0.0).toDouble(),
      openInterest: json['oi'] ?? 0,
      oiChangePercent: (json['oi_change_percent'] ?? 0.0).toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch),
      dayHigh: (json['day_high'] ?? 0.0).toDouble(),
      dayLow: (json['day_low'] ?? 0.0).toDouble(),
      buyQuantity: json['total_buy_quantity'] ?? 0,
      sellQuantity: json['total_sell_quantity'] ?? 0,
      change: (json['change'] ?? 0.0).toDouble(),
      changePercent: (json['change_percent'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'instrument': instrument,
      'token': token,
      'ltp': ltp,
      'open': open,
      'high': high,
      'low': low,
      'close': close,
      'volume': volume,
      'vwap': vwap,
      'oi': openInterest,
      'oi_change_percent': oiChangePercent,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'day_high': dayHigh,
      'day_low': dayLow,
      'total_buy_quantity': buyQuantity,
      'total_sell_quantity': sellQuantity,
      'change': change,
      'change_percent': changePercent,
    };
  }
}
