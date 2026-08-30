import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'tv_chart_web.dart' if (dart.library.io) 'tv_chart_stub.dart';

/// Platform-adaptive chart widget.
/// On **web**: renders TradingView Lightweight Charts via an embedded iframe.
///   - Data is fetched in pure JS (no Dart HTTP / no CORS issues)
///   - Dual-proxy fallback: allorigins.win → corsproxy.io
/// On **mobile/desktop**: falls back to [fallbackChild] (the existing SfCartesianChart).
class TvChartWidget extends StatelessWidget {
  final String symbol;
  /// Widget to show on non-web platforms (pass the existing SfCartesianChart).
  final Widget fallbackChild;

  const TvChartWidget({
    super.key,
    required this.symbol,
    required this.fallbackChild,
  });

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return fallbackChild;
    return buildTvChart(symbol);
  }
}
