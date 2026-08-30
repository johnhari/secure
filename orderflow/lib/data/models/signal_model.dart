import 'package:equatable/equatable.dart';

class TradeSignal extends Equatable {
  final String signal; // STRONG_BUY, BUY, HOLD, SELL, STRONG_SELL
  final int confidence; // 0-100
  final int compositeScore; // -100 to +100
  final Map<String, int> scores; // { orderflow, pattern, sentiment }
  final List<String> patterns;
  final String orderflowSummary;
  final String sentimentLabel;
  final String reasoning;
  final String instrument;
  final DateTime timestamp;

  const TradeSignal({
    required this.signal,
    required this.confidence,
    required this.compositeScore,
    required this.scores,
    required this.patterns,
    required this.orderflowSummary,
    required this.sentimentLabel,
    required this.reasoning,
    required this.instrument,
    required this.timestamp,
  });

  bool get isBullish => signal == 'STRONG_BUY' || signal == 'BUY';
  bool get isBearish => signal == 'STRONG_SELL' || signal == 'SELL';
  bool get isStrong => signal == 'STRONG_BUY' || signal == 'STRONG_SELL';
  bool get isHold => signal == 'HOLD';

  String get signalLabel => signal.replaceAll('_', ' ');

  String get signalEmoji {
    switch (signal) {
      case 'STRONG_BUY': return '🟢🟢';
      case 'BUY': return '🟢';
      case 'STRONG_SELL': return '🔴🔴';
      case 'SELL': return '🔴';
      default: return '⚪';
    }
  }

  factory TradeSignal.fromRTDB(Map<String, dynamic> json) {
    final scoresRaw = json['scores'] as Map<dynamic, dynamic>? ?? {};
    final patternsRaw = json['patterns'] as List<dynamic>? ?? [];

    return TradeSignal(
      signal: json['signal'] as String? ?? 'HOLD',
      confidence: (json['confidence'] as num?)?.toInt() ?? 0,
      compositeScore: (json['compositeScore'] as num?)?.toInt() ?? 0,
      scores: {
        'orderflow': (scoresRaw['orderflow'] as num?)?.toInt() ?? 0,
        'pattern': (scoresRaw['pattern'] as num?)?.toInt() ?? 0,
        'sentiment': (scoresRaw['sentiment'] as num?)?.toInt() ?? 0,
      },
      patterns: patternsRaw.map((e) => e.toString()).toList(),
      orderflowSummary: json['orderflowSummary'] as String? ?? '',
      sentimentLabel: json['sentimentLabel'] as String? ?? 'NEUTRAL',
      reasoning: json['reasoning'] as String? ?? '',
      instrument: json['instrument'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (json['timestamp'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  @override
  List<Object?> get props => [
    signal, confidence, compositeScore, scores, patterns,
    orderflowSummary, sentimentLabel, reasoning, instrument, timestamp,
  ];
}
