import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/audio_service.dart';
import '../../data/models/candle_model.dart';
import '../providers/providers.dart';
import '../providers/instrument_provider.dart';
import '../providers/auth_provider.dart';
import '../../domain/services/orderflow_service.dart';

class ReplayPlayerDialog extends ConsumerStatefulWidget {
  const ReplayPlayerDialog({super.key});

  @override
  ConsumerState<ReplayPlayerDialog> createState() => _ReplayPlayerDialogState();
}

class _ReplayPlayerDialogState extends ConsumerState<ReplayPlayerDialog> with TickerProviderStateMixin {
  // Config selection state
  String _selectedSymbol = 'NIFTY50';
  DateTime _selectedDate = DateTime.now().subtract(const Duration(days: 1));
  
  // Audio state
  bool _isSoundEnabled = true;

  // Data Loading state
  bool _isLoading = false;
  List<CandleModel> _allCandles = [];
  Map<String, Map<String, dynamic>> _orderflowData = {};
  
  // Replay play state
  bool _isPlaying = false;
  int _currentIndex = -1;
  double _playbackSpeed = 1.0; // 1x, 2x, 5x, 10x, 20x
  Timer? _playbackTimer;

  // Played alerts set to avoid duplicate sound spams
  final Set<String> _playedAlerts = {};
  
  // Scroll Controller for tape reader log
  final ScrollController _tapeScrollController = ScrollController();
  final List<String> _tapeLog = [];

  // Ticker for pulsing rings
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Animated Y-Axis bounds & X-Axis scroll
  late AnimationController _axisController;
  Animation<double>? _yMinAnimation;
  Animation<double>? _yMaxAnimation;
  Animation<double>? _xMinAnimation;
  Animation<double>? _xMaxAnimation;

  double _targetYMin = 0.0;
  double _targetYMax = 0.0;
  double _currentYMin = 0.0;
  double _currentYMax = 0.0;

  double _targetXMin = 0.0;
  double _targetXMax = 0.0;
  double _currentXMin = 0.0;
  double _currentXMax = 0.0;

  CategoryAxisController? _xAxisController;

  @override
  void initState() {
    super.initState();
    _selectedSymbol = ref.read(selectedInstrumentProvider);
    // Default to a weekday if yesterday was a weekend
    if (_selectedDate.weekday == 6) {
      _selectedDate = _selectedDate.subtract(const Duration(days: 1)); // Friday
    } else if (_selectedDate.weekday == 7) {
      _selectedDate = _selectedDate.subtract(const Duration(days: 2)); // Friday
    }

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    _axisController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _axisController.addListener(() {
      setState(() {
        _currentYMin = _yMinAnimation?.value ?? _currentYMin;
        _currentYMax = _yMaxAnimation?.value ?? _currentYMax;
        
        final double xMin = _xMinAnimation?.value ?? _currentXMin;
        final double xMax = _xMaxAnimation?.value ?? _currentXMax;
        _currentXMin = xMin;
        _currentXMax = xMax;
        if (_xAxisController != null) {
          _xAxisController!.visibleMinimum = xMin;
          _xAxisController!.visibleMaximum = xMax;
        }
      });
    });

    // Initial load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSessionData();
    });
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _pulseController.dispose();
    _axisController.dispose();
    _tapeScrollController.dispose();
    super.dispose();
  }

  // Load candles and Firestore orderflow
  Future<void> _loadSessionData() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
      _isPlaying = false;
      _allCandles = [];
      _orderflowData = {};
      _currentIndex = -1;
      _tapeLog.clear();
      _playedAlerts.clear();
      _targetYMin = 0.0;
      _targetYMax = 0.0;
      _currentYMin = 0.0;
      _currentYMax = 0.0;
      _targetXMin = 0.0;
      _targetXMax = 0.0;
      _currentXMin = 0.0;
      _currentXMax = 0.0;
    });
    _playbackTimer?.cancel();

    try {
      final symbol = _selectedSymbol;
      final date = _selectedDate;

      // 1. Fetch historical candles from Yahoo
      final candles = await ref.read(candleRepositoryProvider).fetchCandlesForDate(symbol, date);
      
      // 2. Fetch historical orderflow from Firestore
      final orderflow = await ref.read(orderflowServiceProvider).getOrderflowForDate(symbol, date);

      if (mounted) {
        setState(() {
          // Sort candles chronologically
          _allCandles = List.from(candles)..sort((a, b) => a.timeStart.compareTo(b.timeStart));
          _orderflowData = orderflow;
          _isLoading = false;
          
          if (_allCandles.isNotEmpty) {
            _currentIndex = 0;
            _addTapeLog('System: Loaded ${_allCandles.length} candles for $symbol.');
            _processCurrentCandleAlert();
          } else {
            _addTapeLog('Warning: No candle data found for $symbol on ${DateFormat('yyyy-MM-dd').format(date)}.');
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _addTapeLog('Error: Failed to load session data: $e');
        });
      }
    }
  }

  void _addTapeLog(String message) {
    if (!mounted) return;
    setState(() {
      _tapeLog.add(message);
    });
    // Auto-scroll tape log to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tapeScrollController.hasClients) {
        _tapeScrollController.animateTo(
          _tapeScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Handle Play/Pause
  void _togglePlay() {
    if (_allCandles.isEmpty) return;

    if (_isPlaying) {
      _pauseReplay();
    } else {
      _startReplay();
    }
  }

  void _startReplay() {
    if (_currentIndex >= _allCandles.length - 1) {
      // Restart if at the end
      setState(() {
        _currentIndex = 0;
        _tapeLog.clear();
        _playedAlerts.clear();
        _addTapeLog('System: Restarting Replay from beginning.');
      });
    }

    setState(() {
      _isPlaying = true;
    });

    _scheduleNextTick();
  }

  void _pauseReplay() {
    _playbackTimer?.cancel();
    setState(() {
      _isPlaying = false;
    });
    _addTapeLog('System: Playback Paused.');
  }

  void _scheduleNextTick() {
    _playbackTimer?.cancel();
    if (!_isPlaying || _currentIndex >= _allCandles.length - 1) {
      setState(() {
        _isPlaying = false;
      });
      if (_currentIndex >= _allCandles.length - 1) {
        _addTapeLog('System: Replay Completed.');
      }
      return;
    }

    // Speed formula: Base interval of 1500ms divided by playbackSpeed
    final intervalMs = (1500 / _playbackSpeed).round();
    _playbackTimer = Timer(Duration(milliseconds: intervalMs), () {
      if (mounted && _isPlaying) {
        setState(() {
          _currentIndex++;
          _processCurrentCandleAlert();
        });
        _scheduleNextTick();
      }
    });
  }

  // Step controls
  void _stepForward() {
    if (_allCandles.isEmpty || _currentIndex >= _allCandles.length - 1) return;
    _pauseReplay();
    setState(() {
      _currentIndex++;
      _processCurrentCandleAlert();
    });
  }

  void _stepBackward() {
    if (_allCandles.isEmpty || _currentIndex <= 0) return;
    _pauseReplay();
    setState(() {
      _currentIndex--;
      // Don't trigger sound alerts on backward stepping
    });
  }

  // Set speed
  void _setSpeed(double speed) {
    setState(() {
      _playbackSpeed = speed;
    });
    if (_isPlaying) {
      // Reschedule timer immediately with new speed
      _scheduleNextTick();
    }
  }

  String? _findActiveOrderflowKey(CandleModel candle) {
    final String tsKey = candle.timeStart.millisecondsSinceEpoch.toString();
    final String candleKey = candle.candleKey;
    if (_orderflowData.containsKey(tsKey)) return tsKey;
    if (_orderflowData.containsKey(candleKey)) return candleKey;
    
    final candleMs = candle.timeStart.millisecondsSinceEpoch;
    for (final entryKey in _orderflowData.keys) {
      final part = entryKey.contains('_') ? entryKey.split('_').last : entryKey;
      final entryTime = int.tryParse(part);
      if (entryTime != null && entryTime > 0) {
        final actualMs = entryTime < 10000000000 ? entryTime * 1000 : entryTime;
        if (actualMs == candleMs) {
          return entryKey;
        }
      }
    }
    
    for (final entryKey in _orderflowData.keys) {
      final part = entryKey.contains('_') ? entryKey.split('_').last : entryKey;
      final entryTime = int.tryParse(part);
      if (entryTime != null && entryTime > 0) {
        final actualMs = entryTime < 10000000000 ? entryTime * 1000 : entryTime;
        final diff = (actualMs - candleMs).abs();
        if (diff < 5 * 60 * 1000) {
          final candleBucket = candleMs ~/ (5 * 60 * 1000);
          final entryBucket = actualMs ~/ (5 * 60 * 1000);
          if (candleBucket == entryBucket) {
            return entryKey;
          }
        }
      }
    }
    return null;
  }

  // Analyze the newly revealed candle at _currentIndex for alerts and logs
  void _processCurrentCandleAlert() {
    if (_currentIndex < 0 || _currentIndex >= _allCandles.length) return;
    
    final candle = _allCandles[_currentIndex];
    final String? activeKey = _findActiveOrderflowKey(candle);
    
    final timeStr = DateFormat('hh:mm a').format(candle.timeStart);
    final isGreen = candle.close >= candle.open;

    int buyerCount = 0;
    int sellerCount = 0;
    bool isInstitutional = false;
    bool isBigSignal = false;
    bool isTrap = false;
    bool isLiquidation = false;
    bool hasAdminData = false;

    if (activeKey != null) {
      final data = _orderflowData[activeKey]!;
      hasAdminData = (data['injectedBy'] as String?) != null;
      
      num safeParse(dynamic val) {
        if (val is num) return val;
        if (val is String) return num.tryParse(val) ?? 0;
        return 0;
      }

      buyerCount = safeParse(data['buyerCount']).toInt();
      sellerCount = safeParse(data['sellerCount']).toInt();
      isInstitutional = data['isInstitutional'] as bool? ?? false;
      isBigSignal = data['isBigSignal'] as bool? ?? false;
      isTrap = data['isTrap'] as bool? ?? false;
      isLiquidation = data['isLiquidation'] as bool? ?? false;
    } else {
      // Simulated calculations
      final keyInt = candle.timeStart.millisecondsSinceEpoch;
      final random = math.Random(keyInt);
      final diff = (candle.close - candle.open).abs();
      final isBankNifty = _selectedSymbol.contains('BANKNIFTY');

      if (isBankNifty) {
        if (diff > 40) {
          buyerCount = 15000 + random.nextInt(10000);
          sellerCount = 1000 + random.nextInt(3000);
        } else {
          buyerCount = 800 + random.nextInt(3000);
          sellerCount = 800 + random.nextInt(3000);
        }
      } else {
        if (diff > 15) {
          buyerCount = 8000 + random.nextInt(6000);
          sellerCount = 500 + random.nextInt(1500);
        } else {
          buyerCount = 500 + random.nextInt(2000);
          sellerCount = 500 + random.nextInt(2000);
        }
      }

      if (!isGreen) {
        final temp = buyerCount;
        buyerCount = sellerCount;
        sellerCount = temp;
      }
    }

    final dominantCount = buyerCount > sellerCount ? buyerCount : sellerCount;
    final isBuyerDominant = buyerCount > sellerCount;
    final formattedCount = _formatNumber(dominantCount, fullNumber: hasAdminData);

    // Build log message
    String alertTag = "";
    if (isTrap) {
      alertTag = isBuyerDominant ? "⚠️ BUY TRAP" : "⚠️ SELL TRAP";
    } else if (isLiquidation) {
      alertTag = isBuyerDominant ? "⚡ BUY LIQUIDATION" : "⚡ SELL LIQUIDATION";
    } else if (isBigSignal) {
      alertTag = "🔥 BIG SIGNAL";
    } else if (isInstitutional) {
      alertTag = "💼 INSTITUTIONAL";
    } else if (buyerCount >= 8500 || sellerCount >= 8500) {
      alertTag = "📊 HEAVY ACTIVITY";
    }

    final directionStr = isBuyerDominant ? 'BUYS' : 'SELLS';
    final logColorSymbol = isBuyerDominant ? '🟢' : '🔴';
    final logText = '$logColorSymbol [$timeStr] $formattedCount $directionStr vs ${_formatNumber(isBuyerDominant ? sellerCount : buyerCount)} ${isTrap || isLiquidation || isBigSignal || isInstitutional ? "[$alertTag]" : ""}';

    _addTapeLog(logText);

    // Audio Playback
    final alertKey = '${_selectedSymbol}_${candle.timeStart.millisecondsSinceEpoch}';
    if (!_playedAlerts.contains(alertKey)) {
      _playedAlerts.add(alertKey);
      
      final bool triggersSound = isInstitutional || isBigSignal || isTrap || isLiquidation || buyerCount >= 8500 || sellerCount >= 8500;
      if (triggersSound && _isSoundEnabled) {
        AudioService.playTradeSound(
          isInstitutional: isInstitutional,
          isBig: isBigSignal || isTrap || isLiquidation,
        );
      }
    }
  }

  // Format Helper
  String _formatNumber(int count, {bool fullNumber = false}) {
    if (fullNumber) return count.toString();
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 100000) return '${(count / 1000).round()}K';
    if (count >= 10000) return '${(count / 1000).toStringAsFixed(0)}K';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  void _updateYAxisBounds(List<CandleModel> visibleCandles) {
    if (visibleCandles.isEmpty) return;

    // Auto zoom focused window (EXACTLY 7 CANDLES) to give a clean, auto-centered view of current running candlestick
    const int viewportSize = 7;
    final int startIndex = math.max(0, visibleCandles.length - viewportSize);
    final viewportCandles = visibleCandles.sublist(startIndex);

    final currentCandle = visibleCandles.last;
    final double currentCenter = (currentCandle.high + currentCandle.low) / 2;

    double vMin = viewportCandles.map((c) => c.low).reduce(math.min);
    double vMax = viewportCandles.map((c) => c.high).reduce(math.max);
    
    // Always center vertically on current running candlestick with generous padding
    final double rawSpan = math.max(vMax - vMin, (currentCandle.high - currentCandle.low).abs() * 2.5);
    final double halfSpan = math.max(rawSpan * 0.75, 15.0);

    double finalTargetYMin = currentCenter - halfSpan;
    double finalTargetYMax = currentCenter + halfSpan;

    if (finalTargetYMin == finalTargetYMax) {
      finalTargetYMin -= 1.0;
      finalTargetYMax += 1.0;
    }

    // Right margin spacing: extend X-axis by 5.0 empty candle slots so current candle has clean separation from price axis
    final double finalTargetXMax = (visibleCandles.length - 1 + 5.0).toDouble();
    final double finalTargetXMin = math.max(0.0, finalTargetXMax - (viewportSize + 4.0));

    if (_targetYMin == 0.0 && _targetYMax == 0.0) {
      // First time initialization, set immediately
      setState(() {
        _targetYMin = finalTargetYMin;
        _targetYMax = finalTargetYMax;
        _currentYMin = finalTargetYMin;
        _currentYMax = finalTargetYMax;

        _targetXMin = finalTargetXMin;
        _targetXMax = finalTargetXMax;
        _currentXMin = finalTargetXMin;
        _currentXMax = finalTargetXMax;

        if (_xAxisController != null) {
          _xAxisController!.visibleMinimum = finalTargetXMin;
          _xAxisController!.visibleMaximum = finalTargetXMax;
        }
      });
      return;
    }

    final bool yChanged = (finalTargetYMin - _targetYMin).abs() > 0.01 || (finalTargetYMax - _targetYMax).abs() > 0.01;
    final bool xChanged = (finalTargetXMin - _targetXMin).abs() > 0.01 || (finalTargetXMax - _targetXMax).abs() > 0.01;

    if (yChanged || xChanged) {
      _targetYMin = finalTargetYMin;
      _targetYMax = finalTargetYMax;
      _targetXMin = finalTargetXMin;
      _targetXMax = finalTargetXMax;

      final double startYMin = _currentYMin;
      final double startYMax = _currentYMax;
      final double startXMin = _currentXMin;
      final double startXMax = _currentXMax;

      _axisController.stop();

      final intervalMs = (1500 / _playbackSpeed).round();
      final animDurationMs = (intervalMs * 0.85).round().clamp(150, 1200);
      _axisController.duration = Duration(milliseconds: animDurationMs);

      _yMinAnimation = Tween<double>(begin: startYMin, end: _targetYMin).animate(
        CurvedAnimation(parent: _axisController, curve: Curves.easeOutCubic),
      );
      _yMaxAnimation = Tween<double>(begin: startYMax, end: _targetYMax).animate(
        CurvedAnimation(parent: _axisController, curve: Curves.easeOutCubic),
      );
      _xMinAnimation = Tween<double>(begin: startXMin, end: _targetXMin).animate(
        CurvedAnimation(parent: _axisController, curve: Curves.easeOutCubic),
      );
      _xMaxAnimation = Tween<double>(begin: startXMax, end: _targetXMax).animate(
        CurvedAnimation(parent: _axisController, curve: Curves.easeOutCubic),
      );

      _axisController.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isAdmin = authState.user?.isAdmin ?? false;
    final isSuperuser = OrderflowService.isSuperuser(authState.user?.email);
    if (!isAdmin && !isSuperuser) {
      return const SizedBox.shrink();
    }

    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 900;
    
    final currentInstrument = ref.watch(selectedInstrumentProvider);
    final dropdownItems = List<String>.from(AppConstants.instruments);
    if (!dropdownItems.contains(currentInstrument)) {
      dropdownItems.add(currentInstrument);
    }
    
    final dialogWidth = math.min(1100.0, size.width * 0.95);
    final dialogHeight = math.min(800.0, size.height * 0.88);

    // List of candles revealed so far
    final visibleCandles = _currentIndex >= 0 && _allCandles.isNotEmpty
        ? _allCandles.sublist(0, _currentIndex + 1)
        : <CandleModel>[];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateYAxisBounds(visibleCandles);
      }
    });

    // Build index map for the visible CategoryAxis
    final Map<String, int> candleIndexMap = {};
    for (int i = 0; i < visibleCandles.length; i++) {
      candleIndexMap[visibleCandles[i].candleKey] = i;
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: dialogWidth,
            height: dialogHeight,
            decoration: AppTheme.glassDecoration(
              borderRadius: BorderRadius.circular(24),
              borderColor: AppTheme.primaryCyan.withValues(alpha: 0.15),
              opacity: 0.08,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. HEADER BAR
                _buildHeader(context),
                
                // MAIN CONTENT SPLIT
                Expanded(
                  child: _isLoading
                      ? _buildLoader()
                      : _allCandles.isEmpty
                          ? _buildEmptyState()
                          : isDesktop
                              ? Row(
                                  children: [
                                    Expanded(flex: 7, child: _buildChartSection(visibleCandles, candleIndexMap)),
                                    VerticalDivider(width: 1, color: Colors.white.withValues(alpha: 0.08)),
                                    Expanded(flex: 3, child: _buildTapeSection()),
                                  ],
                                )
                              : Column(
                                  children: [
                                    Expanded(flex: 3, child: _buildChartSection(visibleCandles, candleIndexMap)),
                                    Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                                    Expanded(flex: 2, child: _buildTapeSection()),
                                  ],
                                ),
                ),

                // 3. CONTROLS BAR (BOTTOM)
                if (_allCandles.isNotEmpty && !_isLoading) _buildControlsBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- SUB-WIDGETS BUILDERS ---

  Widget _buildHeader(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;

    final currentInstrument = ref.watch(selectedInstrumentProvider);
    final dropdownItems = List<String>.from(AppConstants.instruments);
    if (!dropdownItems.contains(currentInstrument)) {
      dropdownItems.add(currentInstrument);
    }

    if (isMobile) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.cardColor.withValues(alpha: 0.4),
          border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row 1: Title, Status, and Close Button
            Row(
              children: [
                // Pulse replay dot
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isPlaying ? AppTheme.bullColor : AppTheme.bearColor,
                    boxShadow: [
                      if (_isPlaying)
                        BoxShadow(
                          color: AppTheme.bullColor.withValues(alpha: 0.8),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'HISTORICAL MARKET REPLAY',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        _isPlaying ? 'PLAYBACK STREAMING...' : 'PLAYER PAUSED',
                        style: TextStyle(
                          color: _isPlaying ? AppTheme.primaryCyan : AppTheme.subTextColor,
                          fontSize: 8.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                // Compact Close Button
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 16),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    padding: const EdgeInsets.all(6),
                  ),
                ),              ],
            ),
            const SizedBox(height: 12),
            // Row 2: Symbol Selection & Date Picker
            Row(
              children: [
                // Symbol Dropdown (Flexible)
                Expanded(
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedSymbol,
                        dropdownColor: AppTheme.cardColor,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        items: dropdownItems.map((symbol) {
                          return DropdownMenuItem<String>(
                            value: symbol,
                            child: Text(AppConstants.instrumentNames[symbol] ?? symbol),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedSymbol = val);
                            _loadSessionData();
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Date Picker Button (Flexible)
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 60)),
                        lastDate: DateTime.now().subtract(const Duration(days: 1)),
                        builder: (context, child) {
                          return Theme(
                            data: ThemeData.dark().copyWith(
                              colorScheme: const ColorScheme.dark(
                                primary: AppTheme.primaryCyan,
                                onPrimary: Colors.white,
                                surface: AppTheme.cardColor,
                                onSurface: Colors.white,
                              ),
                              dialogTheme: const DialogThemeData(
                                backgroundColor: AppTheme.bgColor,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setState(() => _selectedDate = picked);
                        _loadSessionData();
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.calendar_today_rounded, color: AppTheme.primaryCyan, size: 11),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat('dd MMM, yyyy').format(_selectedDate),
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor.withValues(alpha: 0.4),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1)),
      ),
      child: Row(
        children: [
          // Pulse replay dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isPlaying ? AppTheme.bullColor : AppTheme.bearColor,
              boxShadow: [
                if (_isPlaying)
                  BoxShadow(
                    color: AppTheme.bullColor.withValues(alpha: 0.8),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'HISTORICAL MARKET REPLAY',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
                Text(
                  _isPlaying ? 'PLAYBACK STREAMING...' : 'PLAYER PAUSED',
                  style: TextStyle(
                    color: _isPlaying ? AppTheme.primaryCyan : AppTheme.subTextColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          
          // Symbol Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedSymbol,
                dropdownColor: AppTheme.cardColor,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                items: dropdownItems.map((symbol) {
                  return DropdownMenuItem<String>(
                    value: symbol,
                    child: Text(AppConstants.instrumentNames[symbol] ?? symbol),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedSymbol = val);
                    _loadSessionData();
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Date Picker Button
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime.now().subtract(const Duration(days: 60)),
                lastDate: DateTime.now().subtract(const Duration(days: 1)),
                builder: (context, child) {
                  return Theme(
                    data: ThemeData.dark().copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: AppTheme.primaryCyan,
                        onPrimary: Colors.white,
                        surface: AppTheme.cardColor,
                        onSurface: Colors.white,
                      ),
                      dialogTheme: const DialogThemeData(
                        backgroundColor: AppTheme.bgColor,
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null) {
                setState(() => _selectedDate = picked);
                _loadSessionData();
              }
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, color: AppTheme.primaryCyan, size: 13),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('dd MMM, yyyy').format(_selectedDate),
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Close Button
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white60),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              hoverColor: AppTheme.bearColor.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoader() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.primaryCyan.withValues(alpha: 0.1), width: 1.5),
            ),
            child: const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryCyan),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'AGGREGATING SESSION DATA...',
            style: TextStyle(
              color: AppTheme.primaryCyan,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Syncing Yahoo 5m candles & Firestore orderflows',
            style: TextStyle(
              color: AppTheme.subTextColor,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.bearColor.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.folder_off_outlined, color: AppTheme.bearColor, size: 36),
          ),
          const SizedBox(height: 16),
          const Text(
            'NO DATA FOR THIS DATE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Markets might have been closed, or date is out of range.\nTry selecting a recent weekday.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.subTextColor,
              fontSize: 10,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // --- CHART AREA ---
  Widget _buildChartSection(List<CandleModel> candles, Map<String, int> candleIndexMap) {
    if (candles.isEmpty) return const SizedBox.shrink();

    // Auto calculate visible range
    final double yMin = candles.map((c) => c.low).reduce(math.min);
    final double yMax = candles.map((c) => c.high).reduce(math.max);
    final double pad = (yMax - yMin) * 0.05;

    final latestPrice = candles.isNotEmpty ? candles.last.close : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      color: Colors.transparent,
      child: ClipRect(
        clipBehavior: Clip.hardEdge,
        child: SfCartesianChart(
          plotAreaBorderWidth: 0,
          backgroundColor: Colors.transparent,
          margin: EdgeInsets.zero,
          
          trackballBehavior: TrackballBehavior(
            enable: true,
            activationMode: ActivationMode.singleTap,
            tooltipDisplayMode: TrackballDisplayMode.groupAllPoints,
            lineType: TrackballLineType.vertical,
            lineColor: Colors.white.withValues(alpha: 0.2),
            lineWidth: 0.5,
            lineDashArray: const [4, 4],
            tooltipSettings: const InteractiveTooltip(
              enable: true,
              color: AppTheme.cardColor,
              textStyle: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w900),
            ),
          ),

          primaryXAxis: CategoryAxis(
            onRendererCreated: (CategoryAxisController controller) {
              _xAxisController = controller;
            },
            axisLabelFormatter: (AxisLabelRenderDetails details) {
              final rawText = details.text;
              String cleanText = rawText.contains('_') ? rawText.split('_').last : rawText;
              cleanText = cleanText.replaceAll(',', '').trim();
              int? ms = int.tryParse(cleanText);
              if (ms != null && ms > 0) {
                if (ms < 10000000000) ms *= 1000;
                final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
                return ChartAxisLabel(
                  DateFormat('hh:mm').format(dt),
                  details.textStyle,
                );
              }
              return ChartAxisLabel(rawText, details.textStyle);
            },
            majorGridLines: const MajorGridLines(width: 0.5, color: Color(0xFF2A2E39)),
            axisLine: const AxisLine(width: 0),
            labelStyle: const TextStyle(color: AppTheme.dimTextColor, fontSize: 8, fontWeight: FontWeight.bold),
            majorTickLines: const MajorTickLines(size: 0),
            edgeLabelPlacement: EdgeLabelPlacement.shift,
            labelIntersectAction: AxisLabelIntersectAction.hide,
          ),

          primaryYAxis: NumericAxis(
            minimum: _currentYMin != 0.0 ? _currentYMin : (yMin - pad),
            maximum: _currentYMax != 0.0 ? _currentYMax : (yMax + pad),
            majorGridLines: const MajorGridLines(width: 0.5, color: Color(0xFF2A2E39)),
            minorGridLines: const MinorGridLines(width: 0),
            axisLine: const AxisLine(width: 0),
            labelStyle: const TextStyle(color: AppTheme.dimTextColor, fontSize: 8, fontWeight: FontWeight.bold),
            majorTickLines: const MajorTickLines(size: 0),
            tickPosition: TickPosition.inside,
            decimalPlaces: 0,
            plotBands: <PlotBand>[
              if (latestPrice > 0) () {
                final bool isBull = candles.isNotEmpty && candles.last.close >= candles.last.open;
                final Color liveColor = isBull ? const Color(0xFF26A69A) : const Color(0xFFEF5350);
                return PlotBand(
                  isVisible: true,
                  start: latestPrice,
                  end: latestPrice,
                  shouldRenderAboveSeries: true,
                  borderColor: liveColor.withValues(alpha: 0.85),
                  borderWidth: 1.2,
                  dashArray: const [4, 3],
                  text: '  ${latestPrice.toStringAsFixed(2)}  ',
                  textStyle: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    backgroundColor: liveColor,
                  ),
                  horizontalTextAlignment: TextAnchor.end,
                  verticalTextAlignment: TextAnchor.middle,
                );
              }(),
            ],
          ),

          series: <CartesianSeries<dynamic, String>>[
            CandleSeries<CandleModel, String>(
              dataSource: candles,
              xValueMapper: (CandleModel c, _) => c.candleKey,
              lowValueMapper: (CandleModel c, _) => c.low,
              highValueMapper: (CandleModel c, _) => c.high,
              openValueMapper: (CandleModel c, _) => c.open,
              closeValueMapper: (CandleModel c, _) => c.close,
              bullColor: AppTheme.bullColor,
              bearColor: AppTheme.bearColor,
              enableSolidCandles: true,
              borderWidth: 1,
              animationDuration: 0,
              spacing: 0.15, // Reduced spacing for clearer, wider candlesticks
            ),
          ],

          // Draw orderflow overlays dynamically
          annotations: _buildReplayAnnotations(candles, candleIndexMap),
        ),
      ),
    );
  }

  // Renders the glowing orderflow bubble annotations for the replay view
  List<CartesianChartAnnotation> _buildReplayAnnotations(
    List<CandleModel> candles,
    Map<String, int> candleIndexMap,
  ) {
    final annotations = <CartesianChartAnnotation>[];

    for (final candle in candles) {
      final String? activeKey = _findActiveOrderflowKey(candle);
      
      final range = (candle.high - candle.low).abs();
      final isGreen = candle.close >= candle.open;

      int buyerCount = 0;
      int sellerCount = 0;
      bool isInstitutional = false;
      bool isBigSignal = false;
      bool isTrap = false;
      bool isLiquidation = false;
      bool hasAdminData = false;
      
      double bubbleScale = 5.0;
      double bubbleOpacity = 0.65;
      double bubbleGlow = 0.0;
      bool showLabel = true;
      String customTag = "";

      if (activeKey != null) {
        final data = _orderflowData[activeKey]!;
        hasAdminData = (data['injectedBy'] as String?) != null;
        customTag = data['customTag'] as String? ?? "";
        
        num safeParse(dynamic val) {
          if (val is num) return val;
          if (val is String) return num.tryParse(val) ?? 0;
          return 0;
        }

        buyerCount = safeParse(data['buyerCount']).toInt();
        sellerCount = safeParse(data['sellerCount']).toInt();
        bubbleScale = safeParse(data['bubbleScale']).toDouble();
        if (bubbleScale == 0) bubbleScale = 5.0;

        isBigSignal = data['isBigSignal'] as bool? ?? false;
        isInstitutional = data['isInstitutional'] as bool? ?? false;
        isTrap = data['isTrap'] as bool? ?? false;
        isLiquidation = data['isLiquidation'] as bool? ?? false;
        
        bubbleOpacity = safeParse(data['bubbleOpacity']).toDouble();
        if (bubbleOpacity == 0) bubbleOpacity = 0.65;

        bubbleGlow = safeParse(data['bubbleGlow']).toDouble();
        showLabel = data['showLabel'] as bool? ?? true;
      } else {
        // Simulated Calculations
        final keyInt = candle.timeStart.millisecondsSinceEpoch;
        final random = math.Random(keyInt);
        final diff = (candle.close - candle.open).abs();
        final isBankNifty = _selectedSymbol.contains('BANKNIFTY');

        bubbleScale = isBankNifty ? (range / 40.0).clamp(0.35, 1.15) : (range / 15.0).clamp(0.35, 1.15);

        if (isBankNifty) {
          if (diff > 40) {
            buyerCount = 15000 + random.nextInt(10000);
            sellerCount = 1000 + random.nextInt(3000);
          } else {
            buyerCount = 800 + random.nextInt(3000);
            sellerCount = 800 + random.nextInt(3000);
          }
        } else {
          if (diff > 15) {
            buyerCount = 8000 + random.nextInt(6000);
            sellerCount = 500 + random.nextInt(1500);
          } else {
            buyerCount = 500 + random.nextInt(2000);
            sellerCount = 500 + random.nextInt(2000);
          }
        }

        if (!isGreen) {
          final temp = buyerCount;
          buyerCount = sellerCount;
          sellerCount = temp;
        }
      }

      final isBuyerDominant = buyerCount > sellerCount;
      final dominantCount = isBuyerDominant ? buyerCount : sellerCount;
      final bubbleY = (candle.high + candle.low) / 2;

      // Render Bubble overlay
      if (buyerCount > 0 || sellerCount > 0) {
        if (hasAdminData) {
          // Replay Injected Orderflow Bubble
          annotations.add(CartesianChartAnnotation(
            widget: ReplayEntryAnimation(
              key: ValueKey('bubble_${candle.candleKey}'),
              child: _buildReplayBubbleWidget(
                count: dominantCount,
                isBuyer: isBuyerDominant,
                isHeavy: isBigSignal || isInstitutional || isTrap || isLiquidation,
                scale: bubbleScale,
                opacity: bubbleOpacity,
                glow: bubbleGlow,
                showLabel: showLabel,
                isRealData: hasAdminData,
                isTrap: isTrap,
                isLiquidation: isLiquidation,
                customTag: customTag,
              ),
            ),
            coordinateUnit: CoordinateUnit.point,
            x: candle.candleKey,
            y: bubbleY,
            verticalAlignment: ChartAlignment.center,
            horizontalAlignment: ChartAlignment.center,
          ));
        } else {
          // Replay Simulated Volume Badge: Clean Glass Pill with Buyer / Seller counts
          annotations.add(CartesianChartAnnotation(
            widget: ReplayEntryAnimation(
              key: ValueKey('sim_vol_${candle.candleKey}'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xEE0B0E14),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isGreen ? const Color(0xFF00FF41).withValues(alpha: 0.4) : const Color(0xFFFF003C).withValues(alpha: 0.4),
                    width: 0.8,
                  ),
                  boxShadow: const [
                    BoxShadow(color: Color(0x80000000), blurRadius: 4, offset: Offset(0, 1)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatNumber(buyerCount),
                      style: const TextStyle(
                        color: Color(0xFF00FF41),
                        fontSize: 7.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      _formatNumber(sellerCount),
                      style: const TextStyle(
                        color: Color(0xFFFF003C),
                        fontSize: 7.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            coordinateUnit: CoordinateUnit.point,
            x: candle.candleKey,
            y: bubbleY,
            verticalAlignment: ChartAlignment.center,
            horizontalAlignment: ChartAlignment.center,
          ));
        }

        // Add Signal Tags (Above/Below Candle)
        if (showLabel && (isTrap || isLiquidation) && !hasAdminData) {
          final isHighTag = !isBuyerDominant; // place on opposite side of body
          final prefix = isBuyerDominant ? 'BUY' : 'SELL';
          final tagText = isTrap ? '$prefix TRAP' : '$prefix LIQ';
          annotations.add(CartesianChartAnnotation(
            widget: ReplayEntryAnimation(
              key: ValueKey('tag_${candle.candleKey}'),
              child: _buildSignalTagMini(
                tagText,
                isTrap ? Colors.orangeAccent : Colors.purpleAccent,
              ),
            ),
            coordinateUnit: CoordinateUnit.point,
            x: candle.candleKey,
            y: isHighTag ? candle.high : candle.low,
            verticalAlignment: isHighTag ? ChartAlignment.near : ChartAlignment.far,
            horizontalAlignment: ChartAlignment.center,
          ));
        }
      }
    }

    return annotations;
  }

  Widget _buildReplayBubbleWidget({
    required int count,
    required bool isBuyer,
    required bool isHeavy,
    required double scale,
    required double opacity,
    required double glow,
    required bool showLabel,
    required bool isRealData,
    required bool isTrap,
    required bool isLiquidation,
    String customTag = "",
  }) {
    if (isRealData) {
      return AdminGlowingOrb(
        count: count,
        isBuyer: isBuyer,
        scale: scale,
        customTag: customTag,
        isTrap: isTrap,
        isLiquidation: isLiquidation,
      );
    }

    Color baseColor = isBuyer ? const Color(0xFF00FF41) : const Color(0xFFFF003C);
    if (!isRealData) {
      if (isTrap) {
        baseColor = Colors.orangeAccent;
      } else if (isLiquidation) {
        baseColor = Colors.purpleAccent;
      }
    }

    final glowColor = baseColor.withValues(alpha: opacity + (glow * 0.3));
    double size = 22.0 * scale;
    if (size < 15.0) size = 15.0;
    if (size > 60.0) size = 60.0;

    final core = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Colors.white.withValues(alpha: opacity),
            baseColor.withValues(alpha: opacity),
            baseColor.withValues(alpha: opacity * 0.6),
          ],
          stops: const [0.0, 0.4, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: glowColor,
            blurRadius: 12.0 + (isHeavy ? 6.0 : 0) + (glow * 6.0),
            spreadRadius: 2.0 + (isHeavy ? 2.0 : 0) + (glow * 3.0),
          ),
        ],
      ),
      child: showLabel
          ? Center(
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isRealData ? 6.0 : 4.0,
                  vertical: isRealData ? 4.0 : 2.0,
                ),
                decoration: BoxDecoration(
                  color: isRealData ? baseColor : Colors.black87,
                  borderRadius: BorderRadius.circular(isRealData ? 100 : 4),
                  border: isRealData 
                      ? Border.all(color: Colors.white, width: 1.0)
                      : null,
                ),
                child: Text(
                  _formatNumber(count, fullNumber: isRealData),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: (isRealData ? 9 + scale : 8 + scale).clamp(7.0, 14.0),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            )
          : null,
    );

    if (isHeavy && isRealData) {
      return Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              final progress = _pulseAnimation.value;
              return Container(
                width: size * (1.0 + (progress * 0.6)),
                height: size * (1.0 + (progress * 0.6)),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: baseColor.withValues(alpha: (1.0 - progress).clamp(0.0, 1.0) * 0.7),
                    width: 1.5,
                  ),
                ),
              );
            },
          ),
          core,
        ],
      );
    }

    return core;
  }

  Widget _buildSignalTagMini(String tag, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1),
      ),
      child: Text(
        tag,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // --- TAPE LOG READER SECTION ---
  Widget _buildTapeSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppTheme.cardColor.withValues(alpha: 0.15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ORDERFLOW TAPE READER',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() => _tapeLog.clear());
                  _addTapeLog('System: Tape Cleared.');
                },
                icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white38, size: 16),
                tooltip: 'Clear Tape',
                style: IconButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(24, 24),
                ),
              )
            ],
          ),
          const SizedBox(height: 10),
          
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: ListView.builder(
                controller: _tapeScrollController,
                itemCount: _tapeLog.length,
                itemBuilder: (context, index) {
                  final log = _tapeLog[index];
                  
                  // Custom row styling based on signals
                  Color textColor = Colors.white70;
                  FontWeight weight = FontWeight.w400;
                  
                  if (log.contains('🟢')) {
                    textColor = const Color(0xFF00FF41);
                    weight = FontWeight.w600;
                  } else if (log.contains('🔴')) {
                    textColor = const Color(0xFFFF003C);
                    weight = FontWeight.w600;
                  } else if (log.contains('TRAP')) {
                    textColor = Colors.orangeAccent;
                    weight = FontWeight.w800;
                  } else if (log.contains('LIQUIDATION')) {
                    textColor = Colors.purpleAccent;
                    weight = FontWeight.w800;
                  } else if (log.contains('System:') || log.contains('Warning:')) {
                    textColor = AppTheme.primaryCyan;
                    weight = FontWeight.bold;
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Text(
                      log,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 10,
                        fontWeight: weight,
                        fontFamily: 'monospace',
                        height: 1.3,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- CONTROLS BAR (BOTTOM SCALAR & BUTTONS) ---
  Widget _buildControlsBar() {
    final String currentTimeStr = _currentIndex >= 0 && _currentIndex < _allCandles.length
        ? DateFormat('hh:mm a').format(_allCandles[_currentIndex].timeStart)
        : '--:-- --';
    final String startTimeStr = _allCandles.isNotEmpty
        ? DateFormat('hh:mm a').format(_allCandles.first.timeStart)
        : '09:15 AM';
    final String endTimeStr = _allCandles.isNotEmpty
        ? DateFormat('hh:mm a').format(_allCandles.last.timeStart)
        : '03:40 PM';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor.withValues(alpha: 0.4),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. TIMELINE SLIDER
          Row(
            children: [
              Text(
                startTimeStr,
                style: const TextStyle(color: AppTheme.subTextColor, fontSize: 9, fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3.0,
                    activeTrackColor: AppTheme.primaryCyan,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                    thumbColor: Colors.white,
                    overlayColor: AppTheme.primaryCyan.withValues(alpha: 0.15),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    min: 0,
                    max: math.max(0.0, (_allCandles.length - 1).toDouble()),
                    value: _currentIndex.toDouble().clamp(0.0, math.max(0.0, (_allCandles.length - 1).toDouble())),
                    onChanged: (val) {
                      _pauseReplay();
                      setState(() {
                        _currentIndex = val.round().clamp(0, _allCandles.length - 1);
                        _processCurrentCandleAlert();
                      });
                    },
                  ),
                ),
              ),
              Text(
                endTimeStr,
                style: const TextStyle(color: AppTheme.subTextColor, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          
          const SizedBox(height: 8),

          // 2. PLAYBACK ACTION BUTTONS
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Speed selectors
              Row(
                children: [
                  _buildSpeedButton(1.0),
                  const SizedBox(width: 4),
                  _buildSpeedButton(2.0),
                  const SizedBox(width: 4),
                  _buildSpeedButton(5.0),
                  const SizedBox(width: 4),
                  _buildSpeedButton(10.0),
                  const SizedBox(width: 4),
                  _buildSpeedButton(20.0),
                ],
              ),

              // Player Core controls
              Row(
                children: [
                  // Step back
                  IconButton(
                    onPressed: _currentIndex > 0 ? _stepBackward : null,
                    icon: const Icon(Icons.skip_previous_rounded),
                    color: Colors.white70,
                    disabledColor: Colors.white12,
                    tooltip: 'Step Back (<<)',
                  ),
                  const SizedBox(width: 8),
                  
                  // Play button (Center highlight)
                  ClipOval(
                    child: Container(
                      color: AppTheme.primaryCyan.withValues(alpha: 0.1),
                      child: IconButton(
                        onPressed: _togglePlay,
                        icon: Icon(
                          _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 28,
                        ),
                        color: AppTheme.primaryCyan,
                        padding: const EdgeInsets.all(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Step forward
                  IconButton(
                    onPressed: _currentIndex < _allCandles.length - 1 ? _stepForward : null,
                    icon: const Icon(Icons.skip_next_rounded),
                    color: Colors.white70,
                    disabledColor: Colors.white12,
                    tooltip: 'Step Forward (>>)',
                  ),
                ],
              ),

              // Status elements: audio status & time
              Row(
                children: [
                  // Audio Enable Toggle
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _isSoundEnabled = !_isSoundEnabled;
                        _addTapeLog('System: Audio Alerts ${_isSoundEnabled ? "Enabled" : "Muted"}.');
                      });
                    },
                    icon: Icon(
                      _isSoundEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                      color: _isSoundEnabled ? AppTheme.primaryCyan : Colors.white24,
                    ),
                    tooltip: _isSoundEnabled ? 'Mute Sound Alerts' : 'Unmute Sound Alerts',
                  ),
                  const SizedBox(width: 10),
                  
                  // Time Counter Glass Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text(
                      currentTimeStr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedButton(double speed) {
    final isSelected = _playbackSpeed == speed;
    return InkWell(
      onTap: () => _setSpeed(speed),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryCyan : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.primaryCyan : Colors.white.withValues(alpha: 0.05),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryCyan.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: Text(
          '${speed.toStringAsFixed(0)}x',
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.subTextColor,
            fontSize: 9,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

// ─── ADMIN GLOWING ORB VISUAL (REPLAY) ───

class AdminGlowingOrb extends StatefulWidget {
  final int count;
  final bool isBuyer;
  final double scale;
  final String customTag;
  final bool isTrap;
  final bool isLiquidation;

  const AdminGlowingOrb({
    super.key,
    required this.count,
    required this.isBuyer,
    required this.scale,
    required this.customTag,
    required this.isTrap,
    required this.isLiquidation,
  });

  @override
  State<AdminGlowingOrb> createState() => _AdminGlowingOrbState();
}

class _AdminGlowingOrbState extends State<AdminGlowingOrb> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Normalize the scale factor: 5.0 maps to 1.0. Clamp between 0.2 (very small) and 4.0 (very large).
    final double baseS = (widget.scale / 5.0).clamp(0.2, 4.0);
    final bool isPc = kIsWeb || 
                      defaultTargetPlatform == TargetPlatform.windows || 
                      defaultTargetPlatform == TargetPlatform.macOS || 
                      defaultTargetPlatform == TargetPlatform.linux;
    final double s = isPc ? baseS * 1.6 : baseS;
    
    Color baseColor = widget.isBuyer ? const Color(0xFF00E676) : const Color(0xFFFF5252);
    
    if (widget.isTrap) {
      baseColor = Colors.orangeAccent;
    } else if (widget.isLiquidation) {
      baseColor = Colors.purpleAccent;
    }

    String tagText = widget.customTag.isNotEmpty 
        ? widget.customTag 
        : (widget.isBuyer ? "BUY" : "SELL");

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        final pulse = _pulseAnimation.value;
        return SizedBox(
          width: 240 * s,
          height: 240 * s,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. Concentric rings expanding outwards
              CustomPaint(
                size: Size(240 * s, 240 * s),
                painter: ConcentricRingsPainter(
                  color: baseColor,
                  scale: s,
                  pulse: pulse,
                ),
              ),
              
              // 2a. Large glowing halo with radial gradient and shadow
              Container(
                width: 140 * s * pulse,
                height: 140 * s * pulse,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      baseColor.withValues(alpha: 0.7),
                      baseColor.withValues(alpha: 0.35),
                      baseColor.withValues(alpha: 0.1),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.4, 0.7, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: baseColor.withValues(alpha: 0.55),
                      blurRadius: 30 * s,
                      spreadRadius: 4 * s,
                    ),
                  ],
                ),
              ),
              
              // 2b. Solid central core ball for distinct visibility
              Container(
                width: 85 * s * pulse,
                height: 85 * s * pulse,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: baseColor.withValues(alpha: 0.95),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.4),
                    width: 1.0 * s,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: baseColor.withValues(alpha: 0.7),
                      blurRadius: 12 * s,
                      spreadRadius: 2 * s,
                    ),
                  ],
                ),
              ),
              
              // 3. Central Column: Tag + Black Number Box
              Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Tag Chip (e.g. BUY / SELL)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 3 * s),
                    decoration: BoxDecoration(
                      color: baseColor.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4 * s),
                      border: Border.all(
                        color: baseColor.withValues(alpha: 0.85),
                        width: 1.0 * s,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: baseColor.withValues(alpha: 0.3),
                          blurRadius: 4 * s,
                          spreadRadius: 1 * s,
                        ),
                      ],
                    ),
                    child: Text(
                      tagText,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9.0 * s,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0 * s,
                      ),
                    ),
                  ),
                  SizedBox(height: 3 * s),
                  // Black Numeric Box
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 6 * s),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(6 * s),
                      border: Border.all(
                        color: baseColor.withValues(alpha: 0.3),
                        width: 1.0 * s,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 8 * s,
                          offset: Offset(0, 2 * s),
                        ),
                      ],
                    ),
                    child: Text(
                      widget.count.toString(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.0 * s,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class ConcentricRingsPainter extends CustomPainter {
  final Color color;
  final double scale;
  final double pulse;
  
  ConcentricRingsPainter({
    required this.color,
    required this.scale,
    required this.pulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 * scale;
      
    final center = Offset(size.width / 2, size.height / 2);
    
    // Expand rings slightly with the pulse
    final r1 = 65.0 * scale * (1.0 + (pulse - 1.0) * 0.3);
    final r2 = 90.0 * scale * (1.0 + (pulse - 1.0) * 0.4);
    final r3 = 115.0 * scale * (1.0 + (pulse - 1.0) * 0.5);
    
    canvas.drawCircle(center, r1, paint);
    canvas.drawCircle(center, r2, paint);
    canvas.drawCircle(center, r3, paint);
  }

  @override
  bool shouldRepaint(covariant ConcentricRingsPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.scale != scale ||
        oldDelegate.pulse != pulse;
  }
}

// ─── REPLAY OVERLAY ENTRY ANIMATION (POP & FADE) ───

class ReplayEntryAnimation extends StatefulWidget {
  final Widget child;
  const ReplayEntryAnimation({super.key, required this.child});

  @override
  State<ReplayEntryAnimation> createState() => _ReplayEntryAnimationState();
}

class _ReplayEntryAnimationState extends State<ReplayEntryAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}
