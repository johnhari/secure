import 'package:flutter/material.dart';
import '../../data/models/candle_model.dart';

class TradingViewChart extends StatelessWidget {
  final List<CandleModel> candles;
  final String symbol;

  const TradingViewChart({
    super.key,
    required this.candles,
    required this.symbol,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Chart: $symbol',
        style: const TextStyle(color: Colors.white54),
      ),
    );
  }
}
