import 'dart:convert';
import 'dart:js' as js;
import 'dart:ui_web' as ui_web;
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../data/models/candle_model.dart';

class TradingViewChart extends StatefulWidget {
  final List<CandleModel> candles;
  final String symbol;

  const TradingViewChart({
    super.key,
    required this.candles,
    required this.symbol,
  });

  @override
  State<TradingViewChart> createState() => _TradingViewChartState();
}

class _TradingViewChartState extends State<TradingViewChart> {
  late String viewId;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    // Sanitize symbol for DOM ID (remove special chars like ^)
    final sanitizedSymbol = widget.symbol.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    viewId = 'tv_chart_${sanitizedSymbol}_${DateTime.now().millisecondsSinceEpoch}';
    
    debugPrint('🛠️ [WEB] Registering TradingView PlatformView: $viewId');
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(
      viewId,
      (int _) => html.DivElement()
        ..id = viewId
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = '#131722',
    );

    // Give ample time for the platform view to be inserted into the DOM and for Shadow DOM to settle
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) _initChart();
      });
    });
  }

  void _initChart({int attempts = 0}) {
    if (!kIsWeb) return;
    
    // Check if the JS function exists in index.html
    if (js.context.hasProperty('initTvChart')) {
      try {
        final result = js.context.callMethod('initTvChart', [viewId]);
        // If result is undefined or false, it means it's not ready yet
        if (result != null && result != false) {
          if (mounted) {
            setState(() => _isInitialized = true);
            _updateData();
          }
        } else {
          _scheduleRetry(attempts);
        }
      } catch (e) {
        debugPrint('⚠️ [WEB] Error calling initTvChart: $e');
        _scheduleRetry(attempts);
      }
    } else {
      _scheduleRetry(attempts);
    }
  }

  void _scheduleRetry(int attempts) {
    if (attempts < 20) {
      final delay = attempts < 5 ? 1000 : 3000;
      Future.delayed(Duration(milliseconds: delay), () {
        if (mounted) _initChart(attempts: attempts + 1);
      });
    } else {
      debugPrint('❌ [WEB] Failed to initialize chart after 20 attempts');
    }
  }

  void _updateData() {
    if (!kIsWeb || widget.candles.isEmpty) return;

    // Filter out duplicates and sort by time (TV requires ascending unique time)
    final Map<int, Map<String, dynamic>> uniqueData = {};
    for (final c in widget.candles) {
      final time = c.timeStart.millisecondsSinceEpoch ~/ 1000;
      uniqueData[time] = {
        'time': time,
        'open': c.open,
        'high': c.high,
        'low': c.low,
        'close': c.close,
      };
    }
    
    final sortedList = uniqueData.values.toList()
      ..sort((a, b) => (a['time'] as int).compareTo(b['time'] as int));

    // Call the JS function defined in index.html
    try {
      js.context.callMethod('updateTvData', [viewId, js.JsObject.jsify(sortedList)]);
      _isInitialized = true;
    } catch (e) {
      debugPrint('Error updating TV data: $e');
    }
  }

  @override
  void didUpdateWidget(TradingViewChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.candles.length != oldWidget.candles.length || 
        (widget.candles.isNotEmpty && oldWidget.candles.isNotEmpty && 
         widget.candles.last.close != oldWidget.candles.last.close)) {
      _updateData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: viewId);
  }
}
