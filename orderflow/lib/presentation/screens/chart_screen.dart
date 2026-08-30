import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:screen_secure/screen_secure.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/nifty_stocks.dart';
import '../../core/constants/stock_logos.dart';
import '../../data/models/candle_model.dart';
import '../widgets/scrolling_news_ticker.dart';
import '../../data/models/news_item.dart';
import '../../domain/entities/candle.dart';
import '../../domain/entities/ghost_order.dart';
import '../../domain/services/orderflow_service.dart';
import '../../domain/services/global_settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/notification_service.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/market_time_service.dart';
import '../../core/services/audio_service.dart';
import '../providers/auth_provider.dart';
import '../providers/news_provider.dart';

import '../widgets/tradingview_chart.dart';
import '../widgets/futuristic_radar_loader.dart';
import '../providers/candle_provider.dart';
import '../providers/instrument_provider.dart';
import '../providers/global_config_provider.dart';
import '../providers/providers.dart';

import 'admin_panel_screen.dart';
import 'login_screen.dart';
import 'heatmap_screen.dart';
import 'profile_screen.dart';
import 'signal_radar_screen.dart';




class ChartScreen extends ConsumerStatefulWidget {
  const ChartScreen({super.key});

  @override
  ConsumerState<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends ConsumerState<ChartScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  // Dark theme colors
  // Heavy activity threshold
  static const int _heavyThreshold = 5000;

  // Animation for flashing effect
  late AnimationController _flashController;
  late Animation<double> _flashAnimation;
  
  // New animations
  late AnimationController _entryController;
  late AnimationController _pricePulseController;
  late Animation<double> _priceScaleAnimation;
  
  double _lastKnownPrice = 0.0;
  
  // Smoothing animations
  late Ticker _priceTicker;
  final ValueNotifier<double> _animatedCloseNotifier = ValueNotifier<double>(0.0);
  double _targetPrice = 0.0;

  // Orderflow data & alerts
  Map<String, Map<String, dynamic>> orderflowData = {};
  StreamSubscription? _orderflowSubscription;
  final Set<String> _alreadyAlertedCandles = {};
  
  bool _showOrderflowInput = false;
  bool _isSearchingTransition = false;
  String? _transitionSymbol;
  
  // Ghost Orders
  StreamSubscription? _ghostOrdersSubscription;
  List<GhostOrder> _activeGhostOrders = [];
  final Set<String> _triggeredGhostIds = {};
  double? _lastCheckedGhostPrice;
  bool _isInstitutionalSelected = false;
  bool _isBigSignalSelected = false;
  bool _isAdminOnlySelected = false;

  bool _isTrapSelected = false;
  bool _isLiquidationSelected = false;


  
  
  final _buyerController = TextEditingController();
  final _sellerController = TextEditingController();
  final _newsTickerController = TextEditingController();
  final _tickerScrollController = ScrollController();
  DateTime? _selectedCandleTime;
  double _selectedBubbleScale = 5.0;
  double _selectedPulseSpeed = 1.0;
  double _selectedBubbleOpacity = 0.65;
  
  // Long-press Bubble Context
  Offset? _longPressBubblePosition;
  CandleModel? _longPressTargetCandle;
  double? _longPressPrice;
  
  // Advanced Injection
  bool _isGhostMode = false;
  final _ghostTriggerController = TextEditingController();
  
  // Co-movement/similarity scan state
  bool _isScanningSimilarPatterns = false;
  int _scanProgress = 0;
  int _scanTotal = 0;
  List<Map<String, dynamic>> _suggestedSimilarStocks = [];
  final Set<String> _selectedSimilarStocksToInject = {};
  
  // Focus nodes for keyboard shortcuts
  final FocusNode _keyboardFocusNode = FocusNode();
  final _priceLevelController = TextEditingController(); // For footprint
  final _levelBuyerController = TextEditingController();
  final _levelSellerController = TextEditingController();
  
  // Price alerts
  final List<double> _activePriceAlerts = [];
  final List<SmartAlert> _smartAlerts = [];
  // 2. Interaction State
  final ValueNotifier<double?> _pendingAlertPriceNotifier = ValueNotifier<double?>(null);
  ChartSeriesController? _seriesController;
  CategoryAxisController? _xAxisController;
  DateTime? _touchStartTime;
  Offset? _touchStartPosition;

  // Replay animation state variables
  AnimationController? _replayXAxisController;
  Animation<double>? _replayXMinAnimation;
  Animation<double>? _replayXMaxAnimation;
  double _targetReplayXMin = 0.0;
  double _targetReplayXMax = 0.0;
  
  // Update Throttling
  DateTime _lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _throttleTimer;
  
  // Candle Countdown
  Timer? _countdownTimer;
  final ValueNotifier<String> _timeToCloseNotifier = ValueNotifier<String>("05:00");
  final ValueNotifier<bool> _isEndingSoonNotifier = ValueNotifier<bool>(false);
  
  // Axis interaction
  double? _yVisibleMin;
  double? _yVisibleMax;
  double? _xVisibleMin;
  double? _xVisibleMax;
  double? _autoYMin;
  double? _autoYMax;
  double _initialRange = 0.0;
  double _initialMid = 0.0;
  double? _pinchStartMin;
  double? _pinchStartMax;
  Offset? _lastFocalPoint;

  // RAW POINTER PINCH ZOOM tracking
  final Map<int, Offset> _activePointers = {};
  double? _pinchBaseDistance;
  double? _pinchBaseXMin;
  double? _pinchBaseXMax;

  // Auto-scroll to latest candle
  late ZoomPanBehavior _zoomPanBehavior;
  bool _autoScroll = true;
  DateTime? _lastAutoScrollCandle;
  // #9: Track whether a new candle has arrived while user is scrolled left
  bool _newCandleAvailable = false;
  int _lastKnownCandleCount = 0;
  
  bool? _lastAllowAdminScreenshots;
  AppLifecycleState _appState = AppLifecycleState.resumed;
  // Track that we show the update dialog at most once per config change
  bool _updateCheckDone = false;
  String _lastShownUpdateConfigKey = '';
  int _lastShownBroadcastTimestamp = 0;

  // Responsive scaling (Moved up to fields for helper access)
  double _scaleFactor = 1.0;
  bool _isSmallDevice = false;
  double _currentZoomFactor = 1.0;
  double _chartHeight = 300.0; // Default height
  int _autoFadeMinutes = 0; // 0 = No fade

  // ── UX ENHANCEMENTS ──────────────────────────────────────────────────────
  // 1. Double-tap to snap live
  DateTime? _lastTapTime;
  // 2. Candle OHLC HUD on long-press
  CandleModel? _hudCandle;
  Timer? _hudDismissTimer;
  // 4. User zoomed / panned — show RESET button
  bool _hasUserZoomed = false;
  // 5. Zoom level overlay
  final ValueNotifier<String> _zoomLabelNotifier = ValueNotifier<String>('');
  Timer? _zoomLabelTimer;
  // 6. Round-number haptic crossing
  double? _lastCheckedRoundLevel;
  // 8. Candle count for badge

  void _resetAutoZoomAndFit() {
    _autoScroll = true;
    _hasUserZoomed = false;
    _newCandleAvailable = false;
    _xVisibleMin = null;
    _xVisibleMax = null;
    _yVisibleMin = null;
    _yVisibleMax = null;
    _autoYMin = null;
    _autoYMax = null;
    _pinchStartMin = null;
    _pinchStartMax = null;
    _lastAutoScrollCandle = null;
    try {
      _zoomPanBehavior.reset();
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _loadDismissedBroadcast();
    _keyboardFocusNode.requestFocus();
    _zoomPanBehavior = ZoomPanBehavior(
      enablePinching: true,
      enablePanning: true,
      enableDoubleTapZooming: true,
      enableSelectionZooming: false,
      enableMouseWheelZooming: true,
      zoomMode: ZoomMode.x, // Zoom Time axis ONLY (TradingView standard)
      maximumZoomLevel: 0.05,
    );
    
    // Flash animation for heavy activity — NOT started until needed
    _flashController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    _flashAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _flashController, curve: Curves.easeInOut),
    );

    _entryController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _pricePulseController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _priceScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.1).chain(CurveTween(curve: Curves.easeOut)), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 50),
    ]).animate(_pricePulseController);

    // Initialize Price Smoothing Ticker with critically damped lerp (TradingView style)
    _priceTicker = createTicker((elapsed) {
      if (!mounted) return;
      final target = _targetPrice;
      final current = _animatedCloseNotifier.value;
      if (target != 0.0 && current != target) {
        final diff = target - current;
        if (diff.abs() < 0.005) {
          _animatedCloseNotifier.value = target;
        } else {
          // 0.18 factor provides buttery-smooth 60fps TradingView price lerping
          _animatedCloseNotifier.value = current + diff * 0.18;
        }
        _checkGhostOrderTriggers(_animatedCloseNotifier.value);
      }
    });
    // Ticker deferred — will start when first price data arrives

    _entryController.forward();
    
    _setupOrderflowListener();
    _setupGhostOrdersListener();
    _startCountdown();

    WidgetsBinding.instance.addObserver(this);
    
    // Set initial screenshot protection
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        final authState = ref.read(authProvider);
        final user = authState.user;

        if (authState.status == AuthStatus.authenticated && user != null) {
          // #2: RTDB onDisconnect presence — auto-clears when user disconnects
          try {
            final presenceRef = FirebaseDatabase.instance.ref('presence/${user.uid}');
            await presenceRef.set({'online': true, 'lastSeen': ServerValue.timestamp});
            // When connection drops, RTDB server removes the key automatically
            await presenceRef.onDisconnect().remove();
          } catch (e) {
            debugPrint('[PRESENCE] Failed to set RTDB presence: $e');
          }

          // Re-subscribe FCM topics based on subscription plan type
          if (!kIsWeb) {
            try {
              await NotificationService.initialize(
                isIndexOnly: user.isIndexOnly,
              );
            } catch (e) {
              debugPrint('[FCM] Re-init topics failed: $e');
            }
          }
        }

        debugPrint("[SCREEN_PROTECT] Initial check: status=${authState.status}, isAdmin=${user?.isAdmin}");
        _updateScreenshotProtection(user?.isAdmin ?? false, _lastAllowAdminScreenshots ?? false);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appState = state;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Pause heavy animations and timers to prevent lag (e.g. when notification bar is down)
      if (_flashController.isAnimating) _flashController.stop();
      if (_pricePulseController.isAnimating) _pricePulseController.stop();
      if (_priceTicker.isTicking) _priceTicker.stop();
      _countdownTimer?.cancel();
      _orderflowSubscription?.pause(); // STOP processing heavy data streams
    } else if (state == AppLifecycleState.resumed) {
      // Resume
      if (_isHighActivityForFlash) _flashController.repeat(reverse: true);
      if (!_priceTicker.isTicking) _priceTicker.start();
      _startCountdown();
      _orderflowSubscription?.resume(); // Resume data stream processing
      
      // RE-APPLY protection state on resume using cached values
      final authState = ref.read(authProvider);
      _updateScreenshotProtection(authState.user?.isAdmin ?? false, _lastAllowAdminScreenshots ?? false);
    }
  }

  // Helper to track if we should be flashing when resumed
  bool _isHighActivityForFlash = false;

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!MarketTimeService.isMarketOpen()) {
        if (mounted) {
          _timeToCloseNotifier.value = "CLOSED";
          _isEndingSoonNotifier.value = false;
        }
        return;
      }

      final remainingSeconds = MarketTimeService.getRemainingSecondsInCandle();
      
      if (mounted) {
        if (remainingSeconds <= 0) {
          _timeToCloseNotifier.value = "05:00";
          _isEndingSoonNotifier.value = false;
        } else {
          final minutes = (remainingSeconds / 60).floor();
          final seconds = remainingSeconds % 60;
          _timeToCloseNotifier.value = "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
          _isEndingSoonNotifier.value = remainingSeconds <= 30;
        }
      }
    });
  }

  double _getSnappedPrice(double price, List<CandleModel> candles) {
    double snappedPrice = (price * 20).round() / 20; // 0.05 tick size
    
    if (candles.isEmpty) return snappedPrice;

    // 1. Snap to Round Numbers (Multiples of 10, 50, 100)
    final roundLevels = [10.0, 50.0, 100.0];
    for (var level in roundLevels) {
      double nearestRound = (price / level).round() * level;
      if ((price - nearestRound).abs() < (level / 10)) { // 10% proximity
         return nearestRound;
      }
    }

    // 2. Snap to Visible Candle Highs/Lows
    // Only check most recent 20 candles for performance
    final recentCandles = candles.length > 20 ? candles.sublist(candles.length - 20) : candles;
    double minDistance = double.infinity;
    double? candleLevel;

    for (var candle in recentCandles) {
      final hDist = (price - candle.high).abs();
      final lDist = (price - candle.low).abs();
      
      if (hDist < minDistance) {
        minDistance = hDist;
        candleLevel = candle.high;
      }
      if (lDist < minDistance) {
        minDistance = lDist;
        candleLevel = candle.low;
      }
    }

    // If within 5 points, snap to candle level
    if (candleLevel != null && minDistance < 5.0) {
      return candleLevel;
    }

    return snappedPrice;
  }

  void _handleRefresh() {
    setState(() {
      _touchStartTime = null;
      orderflowData.clear(); 
      _alreadyAlertedCandles.clear();
      _triggeredGhostIds.clear();
      _autoScroll = true; // FORCE RESET to live view
    });
    
    // Slight delay to ensure UI clears before reconnecting
    Future.delayed(const Duration(milliseconds: 100), () {
      ref.invalidate(candleStreamProvider);
      _setupOrderflowListener();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chart Refreshed'),
            backgroundColor: AppTheme.primaryCyan,
            duration: Duration(seconds: 1),
          )
        );
      }
    });
  }

  void _showSignalsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: BoxDecoration(
                color: const Color(0xFF070B14).withValues(alpha: 0.95),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.5),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Icon(Icons.bolt_rounded, color: AppTheme.goldColor, size: 24),
                        const SizedBox(width: 8),
                        const Text(
                          'ORDERFLOW SIGNAL RADAR',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.bullColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.bullColor.withValues(alpha: 0.4), width: 1),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.radar_rounded, color: AppTheme.bullColor, size: 12),
                              SizedBox(width: 4),
                              Text(
                                'LIVE SCAN',
                                style: TextStyle(
                                  color: AppTheme.bullColor,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white10, height: 1),
                  Expanded(
                    child: Consumer(
                      builder: (context, ref, child) {
                        final signalsAsync = ref.watch(globalSignalsProvider);
                        
                        return signalsAsync.when(
                          loading: () => const Center(
                            child: CircularProgressIndicator(color: AppTheme.primaryCyan),
                          ),
                          error: (err, stack) => Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Text(
                                'Telemetry failure: $err',
                                style: const TextStyle(color: AppTheme.bearColor, fontSize: 13),
                              ),
                            ),
                          ),
                          data: (signals) {
                            // ── Subscription filter ──
                            final authState = ref.watch(authProvider);
                            final isIndexOnly = authState.user?.isIndexOnly ?? false;
                            final visibleSignals = isIndexOnly
                                ? signals.where((s) =>
                                    NiftyStocks.isIndexOnlyAllowed(s['symbol'] as String? ?? ''))
                                    .toList()
                                : signals;

                            if (visibleSignals.isEmpty) {
                              return const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.sensors_off_rounded, color: Colors.white24, size: 48),
                                    SizedBox(height: 12),
                                    Text(
                                      'NO ACTIVE TELEMETRY SIGNALS',
                                      style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Waiting for admin signal injection...',
                                      style: TextStyle(color: Colors.white24, fontSize: 10),
                                    ),
                                  ],
                                ),
                              );
                            }
                            
                            return ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              itemCount: visibleSignals.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final signal = visibleSignals.elementAt(index);
                                final String symbol = signal['symbol'];
                                final String name = AppConstants.instrumentNames[symbol] ?? symbol;
                                final int candleTime = signal['candleTime'];
                                final int buyerCount = signal['buyerCount'];
                                final int sellerCount = signal['sellerCount'];
                                final bool isInstitutional = signal['isInstitutional'];
                                final bool isBigSignal = signal['isBigSignal'];
                                final bool isTrap = signal['isTrap'];
                                final bool isLiquidation = signal['isLiquidation'];
                                final String customTag = signal['customTag'];
                                
                                final bool isBuy = buyerCount >= sellerCount;
                                final directionColor = isBuy ? AppTheme.bullColor : AppTheme.bearColor;
                                final directionText = isBuy ? 'BUY' : 'SELL';
                                final directionIcon = isBuy ? Icons.trending_up_rounded : Icons.trending_down_rounded;
                                
                                final dt = DateTime.fromMillisecondsSinceEpoch(candleTime);
                                final timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                                
                                return InkWell(
                                  onTap: () {
                                    HapticFeedback.mediumImpact();
                                    Navigator.pop(context);
                                    _triggerSearchTransition(symbol);
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.02),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: directionColor.withValues(alpha: 0.15),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: directionColor.withValues(alpha: 0.1),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(directionIcon, color: directionColor, size: 18),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    symbol,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w900,
                                                      letterSpacing: 0.5,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    timeStr,
                                                    style: TextStyle(
                                                      color: Colors.white.withValues(alpha: 0.3),
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                name,
                                                style: TextStyle(
                                                  color: Colors.white.withValues(alpha: 0.4),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Row(
                                              children: [
                                                if (isTrap)
                                                  _buildSignalBadge('TRAP', Colors.orangeAccent)
                                                else if (isLiquidation)
                                                  _buildSignalBadge('LIQ', Colors.purpleAccent)
                                                else if (isBigSignal)
                                                  _buildSignalBadge('BIG', Colors.yellowAccent)
                                                else if (isInstitutional)
                                                  _buildSignalBadge('INST', AppTheme.primaryCyan)
                                                else if (customTag.isNotEmpty)
                                                  _buildSignalBadge(customTag.toUpperCase(), Colors.white),
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: directionColor.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: directionColor.withValues(alpha: 0.3)),
                                                  ),
                                                  child: Text(
                                                    directionText,
                                                    style: TextStyle(
                                                      color: directionColor,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w900,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${_formatNumber(buyerCount)} vs ${_formatNumber(sellerCount)}',
                                              style: TextStyle(
                                                color: Colors.white.withValues(alpha: 0.6),
                                                fontFamily: 'monospace',
                                                fontSize: 10,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSignalBadge(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Future<void> _selectReplayDate(BuildContext context) async {
    final user = ref.read(authProvider).user;
    final isSuperuser = OrderflowService.isSuperuser(user?.email);
    final isAdmin = (user?.isAdmin ?? false) || isSuperuser;
    if (!isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Replay mode is restricted to Admin users.'), backgroundColor: AppTheme.bearColor),
      );
      return;
    }
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryCyan,
              onPrimary: Colors.black,
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

    if (picked != null && mounted) {
      HapticFeedback.mediumImpact();
      try {
        await ref.read(candleStreamProvider.notifier).startReplay(picked);
        if (mounted) {
          setState(() {
            _autoScroll = true;
            _hudCandle = null;
            _yVisibleMin = null;
            _yVisibleMax = null;
          });
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to start replay: $e'),
              backgroundColor: AppTheme.bearColor,
            ),
          );
        }
      }
    }
  }

  void _setupOrderflowListener() {
    _orderflowSubscription?.cancel();
    final symbol = ref.read(selectedInstrumentProvider);
    final orderflowService = ref.read(orderflowServiceProvider);
    
    final userEmail = ref.read(authProvider).user?.email;
    _orderflowSubscription = orderflowService.getOrderflowStream(symbol, currentUserEmail: userEmail).listen((data) {


      // CRITICAL PERFORMANCE FIX: Strict pause when inactive (notification, background, etc)
      if (!mounted || _appState != AppLifecycleState.resumed) return;

      final now = DateTime.now();
      
      // Always process alerts immediately to ensure they aren't missed
      _checkHeavyActivityAlerts(data);

      // Throttle UI updates to prevent jank (max 1 update per 300ms)
      if (now.difference(_lastUpdateTime).inMilliseconds > 300) {
        _lastUpdateTime = now;
        setState(() => orderflowData = data);
      } else {
        // Schedule an update if one isn't already scheduled
        if (_throttleTimer?.isActive ?? false) return;
        
        _throttleTimer = Timer(const Duration(milliseconds: 300), () {
          if (mounted) {
            _lastUpdateTime = DateTime.now();
            final currentAuth = ref.read(authProvider);
            // Double check authentication before setting state in delayed callback
            if (currentAuth.isAuthenticated) {
              setState(() => orderflowData = data);
            }
          }
        });
      }
    });
  }

  void _checkHeavyActivityAlerts(Map<String, Map<String, dynamic>> data) {
    // Find recent heavy activity
    final now = DateTime.now();
    for (final entry in data.entries) {
      final adminOnly = entry.value['adminOnly'] as bool? ?? false;
      if (adminOnly) continue; // Skip visual/audio alerts for adminOnly injections

      final candleKey = entry.key; // String
      final buyerCount = (entry.value['buyerCount'] as num?)?.toInt() ?? 0;
      final sellerCount = (entry.value['sellerCount'] as num?)?.toInt() ?? 0;
      final updatedAt = (entry.value['updatedAt'] as num?)?.toInt() ?? 0;
      final updateTime = DateTime.fromMillisecondsSinceEpoch(updatedAt);

      
      // Alert for injections in last 30 seconds (NEW injections)
      // Regardless of how old the candle itself is
      if (now.difference(updateTime).inSeconds <= 30) {
        final isBigSignal = entry.value['isBigSignal'] as bool? ?? false;
        final isTrap = entry.value['isTrap'] as bool? ?? false;
        final isLiquidation = entry.value['isLiquidation'] as bool? ?? false;

        // --- Smart Alerts Check ---
        for (final alert in _smartAlerts) {
          if (!alert.isActive) continue;

          if (alert.type == 'signal' && alert.signalType != null) {
            bool trigger = false;
            if (alert.signalType == 'TRAP' && isTrap) trigger = true;
            if (alert.signalType == 'LIQUIDATION' && isLiquidation) trigger = true;
            if (alert.signalType == 'BIG_SIGNAL' && isBigSignal) trigger = true;

            if (trigger) {
              _triggerSmartAlert(alert);
            }
          }

          if (alert.type == 'imbalance' && alert.minImbalancePct != null) {
            if (buyerCount > 0 && sellerCount > 0) {
              final double ratio = buyerCount > sellerCount ? (buyerCount / sellerCount) : (sellerCount / buyerCount);
              final int imbalancePct = (ratio * 100).round();
              if (imbalancePct >= alert.minImbalancePct!) {
                _triggerSmartAlert(alert);
              }
            }
          }
        }

        final rawCandleTime = (entry.value['candleTime'] as num?)?.toInt() ??
            int.tryParse(candleKey.contains('_') ? candleKey.split('_').last : candleKey);

        // 1. Alert for TRAP SIGNAL (Highest Priority)
        if (isTrap && !_alreadyAlertedCandles.contains('${candleKey}_TRAP')) {
          final prefix = buyerCount >= sellerCount ? 'BUY' : 'SELL';
          _showHeavyAlert('$prefix TRAP SIGNAL', buyerCount >= sellerCount ? buyerCount : sellerCount, buyerCount >= sellerCount, candleTime: rawCandleTime);
          AudioService.playTradeSound(isInstitutional: true);
          _alreadyAlertedCandles.add('${candleKey}_TRAP');
          _isHighActivityForFlash = true; 
          if (!_flashController.isAnimating) _flashController.repeat(reverse: true);
        }

        // 2. Alert for LIQUIDATION
        if (isLiquidation && !_alreadyAlertedCandles.contains('${candleKey}_LIQ')) {
          final prefix = buyerCount >= sellerCount ? 'BUY' : 'SELL';
          _showHeavyAlert('$prefix LIQUIDATION', buyerCount >= sellerCount ? buyerCount : sellerCount, buyerCount >= sellerCount, candleTime: rawCandleTime);
          AudioService.playTradeSound(isInstitutional: true);
          _alreadyAlertedCandles.add('${candleKey}_LIQ');
          _isHighActivityForFlash = true;
          if (!_flashController.isAnimating) _flashController.repeat(reverse: true);
        }

        // 3. Alert for BIG SIGNAL
        if (isBigSignal && !_alreadyAlertedCandles.contains('${candleKey}_BIG')) {
          _showHeavyAlert('BIG SIGNAL', buyerCount >= sellerCount ? buyerCount : sellerCount, buyerCount >= sellerCount, candleTime: rawCandleTime);
          AudioService.playTradeSound(isInstitutional: true);
          _alreadyAlertedCandles.add('${candleKey}_BIG');
          _isHighActivityForFlash = true; // Mark high activity
          if (!_flashController.isAnimating) _flashController.repeat(reverse: true);
        }

        // 2. Alert for Heavy Buyers
        if (buyerCount >= _heavyThreshold && !_alreadyAlertedCandles.contains('${candleKey}_BUY')) {
          _showHeavyAlert('HEAVY BUYERS', buyerCount, true, candleTime: rawCandleTime);
          AudioService.playTradeSound(isInstitutional: true);
          _alreadyAlertedCandles.add('${candleKey}_BUY');
          _isHighActivityForFlash = true; // Mark high activity
          if (!_flashController.isAnimating) _flashController.repeat(reverse: true);
        }

        // 3. Alert for Heavy Sellers
        if (sellerCount >= _heavyThreshold && !_alreadyAlertedCandles.contains('${candleKey}_SELL')) {
          _showHeavyAlert('HEAVY SELLERS', sellerCount, false, candleTime: rawCandleTime);
          AudioService.playTradeSound(isInstitutional: true);
          _alreadyAlertedCandles.add('${candleKey}_SELL');
          _isHighActivityForFlash = true; // Mark high activity
          if (!_flashController.isAnimating) _flashController.repeat(reverse: true);
        }
      }
    }
  }

  void _showHeavyAlert(String type, int count, bool isBuyer, {int? candleTime}) {
    if (!mounted) return;

    // Trigger Windows OS Notification with Stock/Index symbol and Volume
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      final activeSymbol = ref.read(selectedInstrumentProvider);
      NotificationService.showWindowsStockNotification(
        symbol: activeSymbol,
        alertType: type,
        volumeCount: count,
        price: _lastKnownPrice > 0 ? _lastKnownPrice : null,
        buyVolume: isBuyer ? count : 0,
        sellVolume: !isBuyer ? count : 0,
        candleTime: candleTime,
      );
    }

    // --- MAINTENANCE MODE BYPASS ---
    final configVal = ref.read(globalConfigProvider).asData?.value ?? {};
    final isMaintenance = configVal['isMaintenanceMode'] ?? false;
    final authState = ref.read(authProvider);
    final isAdmin = authState.user?.isAdmin ?? false;

    if (isMaintenance && !isAdmin) {
      return; // Suppress alerts during maintenance for non-admins
    }
    
    // Show SnackBar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1.2),
              duration: const Duration(milliseconds: 400),
              curve: Curves.elasticOut,
              builder: (context, value, child) => Transform.scale(scale: value, child: child),
              child: Icon(
                type == 'BIG SIGNAL' ? Icons.stars_rounded : 
                type.contains('TRAP') ? Icons.dangerous_rounded :
                type.contains('LIQUIDATION') ? Icons.flash_on_rounded :
                (isBuyer ? Icons.trending_up_rounded : Icons.trending_down_rounded),
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$type DETECTED',
                    style: TextStyle(
                      fontWeight: FontWeight.w900, 
                      fontSize: 12, 
                      letterSpacing: 1.2,
                      color: Colors.white.withValues(alpha: 0.9)
                    ),
                  ),
                  Text(
                    '${_formatNumber(count)} contracts exchanged!',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: (type.contains('TRAP') ? Colors.orangeAccent : 
                          type.contains('LIQUIDATION') ? Colors.purpleAccent :
                          type == 'BIG SIGNAL' ? AppTheme.goldColor :
                          (isBuyer ? const Color(0xFF00E676) : const Color(0xFFFF5252))).withValues(alpha: 0.95),
        duration: const Duration(seconds: 2), // Reduced from 4s to 2s
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
        ),
        elevation: 12,
        margin: const EdgeInsets.only(bottom: 60, left: 16, right: 16),
      ),
    );

  // Local notification removed - users now get SnackBar + Cloud Function push notification only (2 total)
}

  double? _lastCheckedPrice;
  void _checkPriceAlerts(double currentPrice) {
    if (_lastCheckedPrice == null) {
      _lastCheckedPrice = currentPrice;
      return;
    }

    final alertsToRemove = <double>[];
    for (final alertPrice in _activePriceAlerts) {
      // Robust detection: check if alertPrice is within the range [lastChecked, current]
      final double min = _lastCheckedPrice! < currentPrice ? _lastCheckedPrice! : currentPrice;
      final double max = _lastCheckedPrice! > currentPrice ? _lastCheckedPrice! : currentPrice;
      
      if (alertPrice >= min && alertPrice <= max) {
        SmartAlert? matchedSmart;
        for (final a in _smartAlerts) {
          if (a.type == 'price_cross' && a.targetPrice == alertPrice && a.isActive) {
            matchedSmart = a;
            break;
          }
        }

        if (matchedSmart != null) {
          _triggerSmartAlert(matchedSmart);
        } else {
          _triggerPriceAlert(alertPrice);
        }
        alertsToRemove.add(alertPrice);
      }
    }
    
    if (alertsToRemove.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            for (var a in alertsToRemove) {
              _activePriceAlerts.remove(a);
            }
          });
        }
      });
    }
    
    _lastCheckedPrice = currentPrice;

    // 6. Round-number haptic: pulse on crossing every 100-point level
    const double roundStep = 100.0;
    final double currentLevel = (currentPrice / roundStep).floorToDouble() * roundStep;
    if (_lastCheckedRoundLevel != null && _lastCheckedRoundLevel != currentLevel) {
      HapticFeedback.lightImpact();
    }
    _lastCheckedRoundLevel = currentLevel;
  }

  void _triggerSmartAlert(SmartAlert alert) {
    setState(() {
      alert.isActive = false; // Trigger once
    });

    NotificationService.showLocalNotification(
      title: '🎯 SMART ALERT TRIGGERED',
      body: alert.description,
    );

    // Play selected custom sound
    if (alert.soundName == 'imbalance') {
      AudioService.playImbalanceSound();
    } else if (alert.soundName == 'trade') {
      AudioService.playTradeSound(isBig: false);
    } else {
      AudioService.playPriceAlertSound(); // Standard chime loop
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.notifications_active_rounded, color: AppTheme.goldColor, size: 16),
              const SizedBox(width: 8),
              Text(
                'ALERT: ${alert.description}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          backgroundColor: AppTheme.cardColor,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _triggerPriceAlert(double price) {
    // --- MAINTENANCE MODE BYPASS ---
    final configVal = ref.read(globalConfigProvider).asData?.value ?? {};
    final isMaintenance = configVal['isMaintenanceMode'] ?? false;
    final authState = ref.read(authProvider);
    final isAdmin = authState.user?.isAdmin ?? false;

    if (isMaintenance && !isAdmin) {
      return; // Suppress alerts during maintenance for non-admins
    }

    NotificationService.showLocalNotification(
      title: '🎯 PRICE TARGET HIT',
      body: 'Price crossed your alert level: ${price.toStringAsFixed(2)}',
    );
    
    AudioService.playPriceAlertSound(); // Premium "TradingView" style alert sound

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
                child: const Icon(Icons.gps_fixed_rounded, color: AppTheme.goldColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PRICE TARGET REACHED',
                      style: TextStyle(
                        fontWeight: FontWeight.w900, 
                        fontSize: 11, 
                        letterSpacing: 1.1,
                        color: AppTheme.goldColor
                      ),
                    ),
                    Text(
                      'Price crossed ${price.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.cardColor.withValues(alpha: 0.98),
          duration: const Duration(seconds: 2), // Reduced from 5s to 2s
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppTheme.goldColor, width: 1.5),
          ),
        ),
      );
    }
  }

  void _handleTrackpadZoom(double scaleDelta, List<CandleModel> candles) {
    if (_xAxisController == null || candles.isEmpty) return;
    
    // Get current visible range on Time Axis (X-axis)
    double currentMin = _xVisibleMin ?? math.max(0.0, (candles.length - AppConstants.maxVisibleCandles).toDouble());
    double currentMax = _xVisibleMax ?? (candles.length - 1 + 0.8);
    double range = currentMax - currentMin;
    
    // Calculate center of zoom
    double center = currentMin + range / 2.0;
    
    // Apply scale delta smoothly to Time Axis only
    double normalizedDelta = scaleDelta.clamp(-0.25, 0.25);
    double newRange = range * (1.0 + normalizedDelta);
    
    // Constraints: min 8 candles visible, max all candles + 5 padding
    double minRange = 8.0;
    double maxRange = (candles.length + 5).toDouble();
    newRange = newRange.clamp(minRange, maxRange);
    
    double newMin = center - newRange / 2.0;
    double newMax = center + newRange / 2.0;
    
    // Align with bounds
    if (newMin < -1.0) {
      newMin = -1.0;
      newMax = newMin + newRange;
    }
    double maxLimit = (candles.length + 2.0).toDouble();
    if (newMax > maxLimit) {
      newMax = maxLimit;
      newMin = math.max(-1.0, newMax - newRange);
    }
    
    setState(() {
      _xVisibleMin = newMin;
      _xVisibleMax = newMax;
      _yVisibleMin = null; // Clear Y lock so price axis auto-fits visible candles perfectly!
      _yVisibleMax = null;
      _autoScroll = false;
      _hasUserZoomed = true;
    });
    
    _xAxisController!.visibleMinimum = newMin;
    _xAxisController!.visibleMaximum = newMax;
  }

  void _showPriceAlertDialog(double price) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('SET PRICE ALERT', style: TextStyle(color: AppTheme.goldColor, fontWeight: FontWeight.w900, fontSize: 16)),
        content: Text('Notify when price crosses ${price.toStringAsFixed(2)}?', style: const TextStyle(color: Colors.white, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _activePriceAlerts.add(price));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Alert added for ${price.toStringAsFixed(2)}'), backgroundColor: AppTheme.primaryCyan)
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.goldColor, foregroundColor: Colors.black),
            child: const Text('SET ALERT', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showManualAlertDialog() {
    final TextEditingController priceController = TextEditingController(
      text: _lastKnownPrice > 0 ? _lastKnownPrice.toStringAsFixed(2) : '',
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'SET PRICE ALERT',
          style: TextStyle(
            color: AppTheme.goldColor,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter target price level to alert:',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: 'e.g. 24000.50',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.black26,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.goldColor, width: 1.5),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              final double? price = double.tryParse(priceController.text);
              if (price != null && price > 0) {
                setState(() => _activePriceAlerts.add(price));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Alert added for ${price.toStringAsFixed(2)}'),
                    backgroundColor: AppTheme.primaryCyan,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Invalid price entered'),
                    backgroundColor: AppTheme.bearColor,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.goldColor,
              foregroundColor: Colors.black,
            ),
            child: const Text('SET ALERT', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showSmartAlertBuilderDialog() {
    String conditionType = 'price_cross'; // 'price_cross' | 'imbalance' | 'signal'
    final priceController = TextEditingController(text: _lastKnownPrice > 0 ? _lastKnownPrice.toStringAsFixed(2) : '');
    final imbalanceController = TextEditingController(text: '300');
    String selectedSignalType = 'TRAP'; // 'TRAP' | 'LIQUIDATION' | 'BIG_SIGNAL'
    String selectedSound = 'alert'; // 'alert' | 'imbalance' | 'trade'
    final descController = TextEditingController(text: 'My Custom Alert');

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppTheme.goldColor, width: 1.5),
          ),
          title: const Row(
            children: [
              Icon(Icons.add_alert_rounded, color: AppTheme.goldColor, size: 20),
              SizedBox(width: 8),
              Text('SMART ALERT BUILDER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Condition Type Dropdown
                const Text('TRIGGER CONDITION', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: conditionType,
                      dropdownColor: AppTheme.cardColor,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      items: const [
                        DropdownMenuItem(value: 'price_cross', child: Text('PRICE CROSSES LEVEL')),
                        DropdownMenuItem(value: 'imbalance', child: Text('VOLUME IMBALANCE %')),
                        DropdownMenuItem(value: 'signal', child: Text('ORDERFLOW SIGNAL TYPE')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() {
                            conditionType = v;
                            if (v == 'price_cross') {
                              descController.text = "Price crossed target level";
                            } else if (v == 'imbalance') {
                              descController.text = "High volume imbalance detected";
                            } else {
                              descController.text = "$selectedSignalType signal detected";
                            }
                          });
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Dynamic Input based on selection
                if (conditionType == 'price_cross') ...[
                  const Text('TARGET PRICE', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'e.g. 24050.00',
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: Colors.black26,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white10)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.goldColor)),
                    ),
                  ),
                ] else if (conditionType == 'imbalance') ...[
                  const Text('MINIMUM IMBALANCE %', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: imbalanceController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'e.g. 300',
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: Colors.black26,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white10)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.goldColor)),
                    ),
                  ),
                ] else ...[
                  const Text('SIGNAL TYPE', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedSignalType,
                        dropdownColor: AppTheme.cardColor,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        items: const [
                          DropdownMenuItem(value: 'TRAP', child: Text('TRAP SIGNAL')),
                          DropdownMenuItem(value: 'LIQUIDATION', child: Text('LIQUIDATION')),
                          DropdownMenuItem(value: 'BIG_SIGNAL', child: Text('BIG SIGNAL')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setDialogState(() {
                              selectedSignalType = v;
                              descController.text = "$v signal detected";
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Alert Sound Selection
                const Text('ALERT SOUND', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedSound,
                      dropdownColor: AppTheme.cardColor,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      items: const [
                        DropdownMenuItem(value: 'alert', child: Text('STANDARD CHIME')),
                        DropdownMenuItem(value: 'imbalance', child: Text('HEAVY IMBALANCE')),
                        DropdownMenuItem(value: 'trade', child: Text('SHORT TRADE CLICK')),
                      ],
                      onChanged: (v) => setDialogState(() => selectedSound = v ?? 'alert'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Custom Description
                const Text('CUSTOM DESCRIPTION', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                TextField(
                  controller: descController,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'e.g. Nifty price target!',
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: Colors.black26,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white10)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.goldColor)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () {
                final desc = descController.text.trim();
                final double? targetPrice = conditionType == 'price_cross' ? double.tryParse(priceController.text) : null;
                final alert = SmartAlert(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  type: conditionType,
                  targetPrice: targetPrice,
                  minImbalancePct: conditionType == 'imbalance' ? int.tryParse(imbalanceController.text) : null,
                  signalType: conditionType == 'signal' ? selectedSignalType : null,
                  soundName: selectedSound,
                  description: desc.isNotEmpty ? desc : 'Smart Alert triggered',
                );

                setState(() {
                  _smartAlerts.add(alert);
                  if (alert.type == 'price_cross' && alert.targetPrice != null) {
                    _activePriceAlerts.add(alert.targetPrice!);
                  }
                });

                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Smart Alert set: ${alert.description}'),
                    backgroundColor: AppTheme.primaryCyan,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.goldColor, foregroundColor: Colors.black),
              child: const Text('CREATE ALERT', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _loadDismissedBroadcast() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _lastShownBroadcastTimestamp = prefs.getInt('last_dismissed_broadcast_ts') ?? 0;
      });
    } catch (_) {}
  }

  void _showBroadcastDialog(String message, String type, int timestamp) {
    Color themeColor = AppTheme.primaryCyan;
    IconData icon = Icons.info_outline;
    String title = "SYSTEM ANNOUNCEMENT";
    
    if (type == 'warning') {
      themeColor = AppTheme.goldColor;
      icon = Icons.warning_amber_rounded;
      title = "IMPORTANT NOTICE";
    } else if (type == 'error') {
      themeColor = AppTheme.bearColor;
      icon = Icons.gavel_rounded;
      title = "CRITICAL ALERT";
    }

    showDialog(
      context: context,
      barrierDismissible: false, // Force acknowledgement of urgent broadcast
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: themeColor, width: 1.5),
        ),
        title: Row(
          children: [
            Icon(icon, color: themeColor, size: 24),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                color: themeColor,
                fontWeight: FontWeight.w900,
                fontSize: 15,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: themeColor.withValues(alpha: 0.15)),
              ),
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please acknowledge this announcement to close.',
              style: TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('last_dismissed_broadcast_ts', timestamp);
              } catch (_) {}
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor,
              foregroundColor: AppTheme.bgColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('ACKNOWLEDGE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  // ── App Update Check ────────────────────────────────────────────
  Future<void> _checkForUpdate(Map<String, dynamic> config) async {
    if (!mounted) return;
    // APK updates are strictly for Android devices only (not Windows / Web)
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final info = await PackageInfo.fromPlatform();
      final latestVersion = config['latestVersion'] as String? ?? '';
      if (latestVersion.isEmpty) return;

      final updateEnabled = config['updateEnabled'] as bool? ?? false;
      final forceUpdate = config['forceUpdate'] as bool? ?? false;
      final String rawUrl = config['updateUrl'] as String? ?? '';
      String updateUrl = rawUrl.trim();
      if (updateUrl.isEmpty || updateUrl.contains('firebasestorage.googleapis.com')) {
        updateUrl = 'https://orderflowterminal.web.app/app-release.apk';
      }

      if ((updateEnabled || forceUpdate) && _isVersionNewer(latestVersion, info.version)) {
        if (mounted) {
          _showUpdateDialog(
            latestVersion: latestVersion,
            updateUrl: updateUrl,
            changelog: config['changelog'] as String? ?? '',
            forceUpdate: forceUpdate,
          );
        }
      }
    } catch (e) {
      debugPrint('[UPDATE_CHECK] $e');
    }
  }

  bool _isVersionNewer(String remote, String current) {
    try {
      final cleanRemote = remote.replaceAll(RegExp(r'[^0-9.]'), '');
      final cleanCurrent = current.replaceAll(RegExp(r'[^0-9.]'), '');
      final r = cleanRemote.split('.').where((e) => e.isNotEmpty).map(int.parse).toList();
      final c = cleanCurrent.split('.').where((e) => e.isNotEmpty).map(int.parse).toList();
      final maxLen = math.max(r.length, c.length);
      for (int i = 0; i < maxLen; i++) {
        final rv = i < r.length ? r[i] : 0;
        final cv = i < c.length ? c[i] : 0;
        if (rv > cv) return true;
        if (rv < cv) return false;
      }
      return false;
    } catch (_) {
      return remote != current;
    }
  }

  void _showUpdateDialog({
    required String latestVersion,
    required String updateUrl,
    required String changelog,
    required bool forceUpdate,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (ctx) => AppUpdatePromptDialog(
        latestVersion: latestVersion,
        updateUrl: updateUrl,
        changelog: changelog,
        forceUpdate: forceUpdate,
      ),
    );
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    _countdownTimer?.cancel();
    _hudDismissTimer?.cancel();
    _zoomLabelTimer?.cancel();
    _orderflowSubscription?.cancel();
    _ghostOrdersSubscription?.cancel();
    _flashController.dispose();
    _entryController.dispose();
    _replayXAxisController?.dispose();
    _priceTicker.dispose();
    _animatedCloseNotifier.dispose();
    _timeToCloseNotifier.dispose();
    _isEndingSoonNotifier.dispose();
    _zoomLabelNotifier.dispose();
    _seriesController = null;
    _buyerController.dispose();
    _sellerController.dispose();
    _newsTickerController.dispose();
    _tickerScrollController.dispose();
    _ghostTriggerController.dispose();
    _priceLevelController.dispose();
    _levelBuyerController.dispose();
    _levelSellerController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    if (authState.status == AuthStatus.unauthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      });
      return const Scaffold(
        backgroundColor: Color(0xFF060B12),
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryCyan),
        ),
      );
    }
    final candleState = ref.watch(candleStreamProvider);
    final selectedInstrument = ref.watch(selectedInstrumentProvider);
    final newsAsync = ref.watch(marketNewsProvider);
    final rawNewsItems = newsAsync.value ?? [];
    
    List<NewsItem> newsItems = rawNewsItems;
    if (selectedInstrument != AppConstants.nifty50 &&
        selectedInstrument != AppConstants.bankNifty &&
        selectedInstrument != AppConstants.finNifty &&
        selectedInstrument != 'SENSEX' &&
        selectedInstrument.isNotEmpty) {
      final String cleanSymbol = selectedInstrument.toUpperCase().trim();
      final List<String> keywords = [cleanSymbol];
      if (cleanSymbol == 'TCS') {
        keywords.addAll(['TATA CONSULTANCY SERVICES', 'TATA CONSULTANCY', 'TATA']);
      } else if (cleanSymbol == 'INFY') {
        keywords.addAll(['INFOSYS', 'INFY']);
      } else if (cleanSymbol == 'RELIANCE') {
        keywords.addAll(['RELIANCE INDUSTRIES', 'RELIANCE', 'RIL']);
      } else {
        final fullName = AppConstants.instrumentNames[selectedInstrument];
        if (fullName != null) {
          keywords.add(fullName.toUpperCase());
        }
      }

      final filtered = rawNewsItems.where((item) {
        final titleUpper = item.title.toUpperCase();
        final descriptionUpper = (item.description ?? '').toUpperCase();
        return keywords.any((kw) => titleUpper.contains(kw) || descriptionUpper.contains(kw));
      }).toList();

      if (filtered.isNotEmpty) {
        newsItems = filtered;
      }
    }

    // Only show full-screen loading if we are TRULY initializing with no data
    if (authState.status == AuthStatus.initial || 
       (authState.status == AuthStatus.loading && !authState.isGuest && authState.user == null)) {
      return Scaffold(
        backgroundColor: const Color(0xFF060B12),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLoadingLogo(),
              const SizedBox(height: 24),
              const Text(
                'SYNCHRONIZING TERMINAL...',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'SECURE HANDSHAKE: ${authState.status.name.toUpperCase()}',
                style: TextStyle(
                  color: AppTheme.primaryCyan.withValues(alpha: 0.5),
                  fontSize: 10,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 40),

            ],
          ),
        ),
      );
    }



    // Re-setup listener if instrument changes
    ref.listen(selectedInstrumentProvider, (previous, next) {
      if (previous != next) {
        _alreadyAlertedCandles.clear();
        _lastKnownCandleCount = 0;
        _animatedCloseNotifier.value = 0.0;
        _resetAutoZoomAndFit();
        _setupOrderflowListener();
        if (mounted) setState(() {});
      }
    });

    // Auth state listener — redirect to login on unauthenticated
    ref.listen(authProvider, (previous, next) {
      if (next.status == AuthStatus.unauthenticated) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
        return;
      }
      
      if (next.user != null) {
        _updateScreenshotProtection(next.user!.isAdmin, _lastAllowAdminScreenshots ?? false);
      }
    });

    final isSuperuser = OrderflowService.isSuperuser(authState.user?.email);
    final isAdmin = (authState.user?.isAdmin ?? false) || isSuperuser;
    final latestCandle = candleState.candles.isNotEmpty ? candleState.candles.last : null;
    
    // Monitor for price alerts
    if (latestCandle != null) {
      // --- MAINTENANCE MODE BYPASS ---
      final configVal = ref.read(globalConfigProvider).asData?.value ?? {};
      final isMaintenance = configVal['isMaintenanceMode'] ?? false;
      final isAdmin = authState.user?.isAdmin ?? false;

      if (!isMaintenance || isAdmin) {
        // SMOOTHING TRIGGER: Detect price change and update target price for the Ticker
        if (latestCandle.close != _targetPrice) {
          _targetPrice = latestCandle.close;
          // Lazy-start the price ticker on first real data
          if (!_priceTicker.isTicking) _priceTicker.start();
          if (_animatedCloseNotifier.value == 0.0) {
            _animatedCloseNotifier.value = _targetPrice;
          }
        }

        _checkPriceAlerts(latestCandle.close);
        
        // Trigger price pulse if changed
        if (latestCandle.close != _lastKnownPrice) {
          _lastKnownPrice = latestCandle.close;
          _pricePulseController.forward(from: 0.0);
        }

        // AUTO-SCROLL: Update visible window when new candle arrives
        if (_autoScroll && latestCandle.timeStart != _lastAutoScrollCandle) {
          _lastAutoScrollCandle = latestCandle.timeStart;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _autoScroll) {
              setState(() {});
            }
          });
        }

        // Track candles and auto-fit on initial load when graph opens
        final currentCount = candleState.candles.length;
        if (_lastKnownCandleCount == 0 && currentCount > 0) {
          _resetAutoZoomAndFit();
        } else if (!_autoScroll && currentCount > _lastKnownCandleCount) {
          if (!_newCandleAvailable) setState(() => _newCandleAvailable = true);
        }
        _lastKnownCandleCount = currentCount;
      }
    }
    
    // Calculate Session Change (relative to yesterday's close or today's open)
    double priceChange = 0.0;
    double priceChangePercent = 0.0;
    double sessionOpenPrice = 0.0;
    double referencePrice = 0.0;
    
    if (latestCandle != null && candleState.candles.isNotEmpty) {
      final latestDate = latestCandle.timeStart;
      
      // Find today's candles
      final todayCandles = candleState.candles.where((c) => 
        c.timeStart.year == latestDate.year &&
        c.timeStart.month == latestDate.month &&
        c.timeStart.day == latestDate.day
      ).toList();
      
      final todayFirstCandle = todayCandles.isNotEmpty ? todayCandles.first : candleState.candles.first;
      sessionOpenPrice = todayFirstCandle.open.toDouble();
      
      // Find previous trading day's candles (any candle before today's date)
      final prevDayCandles = candleState.candles.where((c) => 
        c.timeStart.isBefore(DateTime(latestDate.year, latestDate.month, latestDate.day))
      ).toList();
      
      referencePrice = prevDayCandles.isNotEmpty 
          ? prevDayCandles.last.close.toDouble() 
          : sessionOpenPrice;
          
      priceChange = (latestCandle.close - referencePrice).toDouble();
      priceChangePercent = referencePrice != 0 
          ? ((priceChange / referencePrice) * 100).toDouble() 
          : 0.0;
    }
    
    final isPointsFromOpenPositive = priceChange >= 0;

    return StreamBuilder<Map<String, dynamic>>(
      stream: GlobalSettingsService.getConfigStream(),
      builder: (context, snapshot) {
        final config = snapshot.data ?? {};
        // Sentiment and Ticker updates handled globally now
        final isMaintenanceMode = config['isMaintenanceMode'] ?? false;
        final allowAdminScreenshots = config['allowAdminScreenshots'] ?? false;
        final isAdmin = authState.user?.isAdmin ?? false;

        // ── Check for app update live stream ───
        if (snapshot.hasData) {
          final updateEnabled = config['updateEnabled'] ?? false;
          final forceUpdate = config['forceUpdate'] ?? false;
          final version = config['latestVersion'] as String? ?? '';
          final configKey = "$version-$updateEnabled-$forceUpdate";
          if ((updateEnabled || forceUpdate) && _lastShownUpdateConfigKey != configKey) {
            _lastShownUpdateConfigKey = configKey;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _checkForUpdate(config);
            });
          }
        }

        // ── Check for urgent broadcast message (Item 10) ───
        if (snapshot.hasData) {
          final broadcastMsg = config['broadcastMessage'] as String? ?? '';
          final broadcastTs = config['broadcastTimestamp'] as int? ?? 0;
          final broadcastType = config['broadcastType'] as String? ?? 'info';
          if (broadcastMsg.isNotEmpty && broadcastTs > _lastShownBroadcastTimestamp) {
            _lastShownBroadcastTimestamp = broadcastTs;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showBroadcastDialog(broadcastMsg, broadcastType, broadcastTs);
            });
          }
        }

        // Apply dynamic screenshot protection ONLY if changed
        if (_lastAllowAdminScreenshots != allowAdminScreenshots) {
          _lastAllowAdminScreenshots = allowAdminScreenshots;
          // Defer to next frame to avoid build conflicts, but only ONCE per change
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _updateScreenshotProtection(isAdmin, allowAdminScreenshots);
            }
          });
        }

        // Responsive Scaling Logic
        final double screenWidth = MediaQuery.of(context).size.width;
        _scaleFactor = (screenWidth / 390).clamp(0.8, 1.2);
        _isSmallDevice = screenWidth < 360;

        final mediaQuery = MediaQuery.of(context);
        final width = mediaQuery.size.width;
        final isDesktop = width > 1100;

        // Use managed focus node
        return KeyboardListener(
          focusNode: _keyboardFocusNode,
          autofocus: true,
          onKeyEvent: (event) {
            if (event is! KeyDownEvent) return;
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.keyN || key == LogicalKeyboardKey.digit1) {
              ref.read(selectedInstrumentProvider.notifier).state = AppConstants.nifty50;
            } else if (key == LogicalKeyboardKey.keyB || key == LogicalKeyboardKey.digit2) {
              ref.read(selectedInstrumentProvider.notifier).state = AppConstants.bankNifty;
            } else if (key == LogicalKeyboardKey.keyR) {
              _handleRefresh();
            } else if (key == LogicalKeyboardKey.keyA && isSuperuser) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPanelScreen()));
            }
          },
          child: OrientationBuilder(
          builder: (context, orientation) {
            final isLandscape = orientation == Orientation.landscape;

            return Scaffold(
              backgroundColor: AppTheme.bgColor,
              body: Stack(
                children: [
                  // Lightweight Ambient Glows (RadialGradient — zero GPU cost)
                  Positioned(
                    top: -100,
                    right: -100,
                    child: Container(
                      width: 350,
                      height: 350,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppTheme.primaryCyan.withValues(alpha: 0.12),
                            AppTheme.primaryCyan.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 250,
                    left: -120,
                    child: Container(
                      width: 300,
                      height: 300,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppTheme.accentPurple.withValues(alpha: 0.10),
                            AppTheme.accentPurple.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 100,
                    right: -80,
                    child: Container(
                      width: 280,
                      height: 280,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppTheme.goldColor.withValues(alpha: 0.08),
                            AppTheme.goldColor.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -120,
                    left: -50,
                    child: Container(
                      width: 320,
                      height: 320,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppTheme.bullColor.withValues(alpha: 0.08),
                            AppTheme.bullColor.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    bottom: false,
                    child: Column(
                      children: [
                        if (isLandscape)
                          ValueListenableBuilder<double>(
                            valueListenable: _animatedCloseNotifier,
                            builder: (context, animatedClose, _) {
                              return _buildLandscapeHeader(
                                selectedInstrument,
                                isSuperuser,
                                isAdmin,
                                animatedClose,
                                referencePrice,
                                candleState.candles.length,
                                candleState.isReplaying,
                              );
                            }
                          )
                        else ...[
                          _buildAnimatedEntry(
                            child: ValueListenableBuilder<double>(
                              valueListenable: _animatedCloseNotifier,
                              builder: (context, animatedClose, _) {
                                return _buildAppBar(
                                  selectedInstrument,
                                  isSuperuser,
                                  isAdmin,
                                  animatedClose,
                                  candleState.isReplaying,
                                );
                              },
                            ),
                            delayMs: 100,
                          ),
                        ],
                        
                        if (isSuperuser && !isLandscape)
                          _buildAnimatedEntry(
                            delayMs: 250,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.goldColor.withValues(alpha: 0.1),
                                border: Border.all(color: AppTheme.goldColor.withValues(alpha: 0.2)),
                              ),
                              child: const Text(
                                '🚀 UNLOCK INSTITUTIONAL BIG SHOT - PRO PREMIUM ACCESS',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppTheme.goldColor, 
                                  fontSize: 10, 
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ),

                        // Main Content Row
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: candleState.candles.isEmpty
                                ? _buildEmptyWidget(candleState)
                                : Column(
                                    children: [
                                      if (!isLandscape) ...[
                                        _buildAnimatedEntry(
                                          child: GestureDetector(
                                            onHorizontalDragEnd: (DragEndDetails details) {
                                              final velocity = details.primaryVelocity ?? 0;
                                              if (velocity.abs() > 400) {
                                                HapticFeedback.selectionClick();
                                                final instruments = [AppConstants.nifty50, AppConstants.bankNifty];
                                                final currentIdx = instruments.indexOf(selectedInstrument);
                                                final nextIdx = velocity < 0
                                                  ? (currentIdx + 1) % instruments.length
                                                  : (currentIdx - 1 + instruments.length) % instruments.length;
                                                ref.read(selectedInstrumentProvider.notifier).state = instruments[nextIdx];
                                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                                  content: Text('Switched to ${AppConstants.instrumentNames[instruments[nextIdx]] ?? instruments[nextIdx]}'),
                                                  backgroundColor: AppTheme.cardColor,
                                                  duration: const Duration(seconds: 1),
                                                  behavior: SnackBarBehavior.floating,
                                                ));
                                              }
                                            },
                                            child: _buildInstrumentSelector(selectedInstrument, isPointsFromOpenPositive),
                                          ),
                                          delayMs: 300,
                                        ),
                                        if (latestCandle != null) 
                                          _buildAnimatedEntry(
                                            child: ValueListenableBuilder<double>(
                                              valueListenable: _animatedCloseNotifier,
                                              builder: (context, animatedClose, _) {
                                                return _buildPriceHeader(
                                                  selectedInstrument,
                                                  latestCandle, 
                                                  animatedClose,
                                                  priceChange, 
                                                  priceChangePercent, 
                                                  sessionOpenPrice,
                                                  isPointsFromOpenPositive,
                                                  candleCount: candleState.candles.length,
                                                );
                                              }
                                            ), 
                                            delayMs: 400
                                          ),
                                      ],
                                      Expanded(
                                        child: _buildAnimatedEntry(
                                          delayMs: 500,
                                          child: ValueListenableBuilder<double>(
                                            valueListenable: _animatedCloseNotifier,
                                            builder: (context, animatedClose, _) {
                                              if (candleState.candles.isEmpty && !candleState.isLoading) {
                                                return Center(
                                                  child: Column(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      const Icon(Icons.analytics_outlined, color: Colors.white24, size: 48),
                                                      const SizedBox(height: 16),
                                                      Text(
                                                        'WAITING FOR DATA PIPELINE...',
                                                        style: TextStyle(
                                                          color: Colors.white.withValues(alpha: 0.3),
                                                          fontSize: 10,
                                                          letterSpacing: 2,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }
                                              if (kIsWeb) {
                                                return TradingViewChart(
                                                  key: ValueKey('tv_$selectedInstrument'),
                                                  candles: candleState.candles,
                                                  symbol: selectedInstrument,
                                                );
                                              }
                                              return _buildChart(
                                                candleState.candles,
                                                animatedClose,
                                                isSuperuser,
                                                sessionOpenPrice,
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                      ScrollingNewsTicker(newsItems: newsItems),
                                    ],
                                  ),
                              ),
                              if (isDesktop) _buildDesktopDashboard(selectedInstrument, isSuperuser),
                            ],
                          ),
                        ),
                        
                        // Orderflow Input Panel (Superuser only)
                        if (isSuperuser && _showOrderflowInput)
                          _buildOrderflowInputPanel(selectedInstrument),
                        
                        // Bottom Bar
                        if (!isLandscape)
                          _buildAnimatedEntry(child: _buildBottomBar(candleState.lastUpdated), delayMs: 600),
                      ],
                    ),
                  ),

                  // --- MAINTENANCE OVERLAY ---
                  if (isMaintenanceMode && !isAdmin)
                    _buildMaintenanceOverlay(),

                  // #8: OFFLINE BANNER
                  if (candleState.isOffline)
                    _buildOfflineBanner(),

                  // #9: NEW CANDLE BADGE
                    if (_newCandleAvailable && !_autoScroll)
                      _buildNewCandleBadge(),
                      
                  // REPLAY CONTROL PANEL
                  if (candleState.isReplaying && (isAdmin || isSuperuser))
                    _buildReplayControlPanel(candleState),

                  // SEARCH TRANSITION OVERLAY
                  if (_isSearchingTransition)
                    _buildTransitionOverlay(),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // --- DESKTOP ENHANCEMENTS ---

  Widget _buildDesktopDashboard(String symbol, bool isSuperuser) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        border: Border(left: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Icon(Icons.dashboard_outlined, color: AppTheme.primaryCyan, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'SIGNAL DASHBOARD',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.5),
                ),
                const Spacer(),
                _buildModernBadge(text: 'LIVE', color: Colors.redAccent),
              ],
            ),
          ),
          const Divider(color: Colors.white10),
          
          const RadarVisualizerFixed(),
          const Divider(color: Colors.white10),
          
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    const PreMarketBiasDashboard(),
                    const Divider(color: Colors.white10),
                    const RadarSignalsList(),
                    const Divider(color: Colors.white10),
                    
                    // Active Ghost Orders
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('RESTING ORDERS', style: TextStyle(color: AppTheme.subTextColor, fontSize: 9, fontWeight: FontWeight.w900)),
                      ),
                    ),
                    _activeGhostOrders.isEmpty 
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: Text('No resting orders', style: TextStyle(color: Colors.white24, fontSize: 10))),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _activeGhostOrders.length,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemBuilder: (context, i) {
                            final g = _activeGhostOrders[i];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 3,
                                    height: 20,
                                    color: g.isTrap ? Colors.orange : AppTheme.goldColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('₹${g.triggerPrice.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                        Text(g.isTrap ? 'TRAP TARGET' : 'INJECTION TARGET', style: const TextStyle(color: AppTheme.subTextColor, fontSize: 8)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    
                    const Divider(color: Colors.white10),
                    
                    // Quick Action Buttons for Web
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _handleRefresh(),
                          icon: const Icon(Icons.refresh_rounded, size: 14),
                          label: const Text('REFRESH TERMINAL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.primaryCyan, width: 1.5),
                            foregroundColor: AppTheme.primaryCyan,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  // --- EXISTING RESPONSIVE METHODS ---

  Widget _buildLandscapeHeader(
    String selectedInstrument, 
    bool isSuperuser, 
    bool isAdmin,
    double animatedPrice, 
    double referencePrice,
    int candleCount,
    bool isReplaying,
  ) {
    final double change = animatedPrice - referencePrice;
    final double changePercent = referencePrice != 0 ? (change / referencePrice) * 100 : 0.0;
    final bool isPositive = change >= 0;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
          ),
          child: Row(
            children: [
              // Logo
              GestureDetector(
                onTap: () {
                  if (!isSuperuser && !isAdmin) return;
                  HapticFeedback.lightImpact();
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPanelScreen()));
                },
                onLongPress: () {
                  if (!isSuperuser && !isAdmin) return;
                  HapticFeedback.heavyImpact();
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPanelScreen()));
                },
                child: Hero(
                  tag: 'logo',
                  child: Container(
                    width: 32,
                    height: 32,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF202026),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1),
                    ),
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: AppTheme.cardColor,
                        child: const Icon(Icons.show_chart_rounded, color: AppTheme.primaryCyan, size: 16),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // App Title
              Flexible(
                child: Text(
                  'MOST ADVANCE ORDERFLOW ANALYZER',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    color: AppTheme.goldColor,
                    fontSize: 10 * _scaleFactor,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    shadows: [
                      Shadow(
                        color: AppTheme.goldColor.withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Current Date Badge (Format: dd-MM-yyyy)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryCyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppTheme.primaryCyan.withValues(alpha: 0.35), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_rounded, color: AppTheme.primaryCyan, size: 10),
                    const SizedBox(width: 4),
                    Text(
                      intl.DateFormat('dd-MM-yyyy').format(DateTime.now()),
                      style: TextStyle(
                        color: AppTheme.primaryCyan,
                        fontSize: 9 * _scaleFactor,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              
              // Instrument Toggle Glowing Bar
              _buildInstrumentGlowingBar(selectedInstrument, isPositive),
              const SizedBox(width: 8),
              _buildIconButton(
                icon: Icons.search_rounded,
                color: AppTheme.primaryCyan,
                tooltip: 'Search Stocks',
                onPressed: () => _openStockSearch(isIndexOnly: false),
              ),
              const SizedBox(width: 16),
              const NetworkSpeedMeter(),
              const Spacer(),
              
              // Actions on the Right
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [

                  _buildIconButton(
                    icon: Icons.campaign_rounded,
                    color: AppTheme.goldColor,
                    tooltip: 'Signal Radar',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SignalRadarScreen()),
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                  _buildIconButton(
                    icon: Icons.grid_view_rounded,
                    color: AppTheme.primaryCyan,
                    tooltip: 'Nifty 50 Heatmap',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const HeatmapScreen()),
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                  _buildIconButton(
                    icon: Icons.person_rounded,
                    color: AppTheme.primaryCyan,
                    tooltip: 'User Profile',
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ProfileScreen()),
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                  if (isAdmin || isSuperuser) ...[
                    if (!isReplaying) ...[
                      _buildIconButton(
                        icon: Icons.history_toggle_off_rounded,
                        color: AppTheme.primaryCyan,
                        tooltip: 'Replay Candlesticks',
                        onPressed: () => _selectReplayDate(context),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactInstrumentChip(String symbol, bool isSelected, Color activeColor) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        ref.read(selectedInstrumentProvider.notifier).state = symbol;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? activeColor : Colors.white.withValues(alpha: 0.05),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.35),
                    blurRadius: 8,
                    spreadRadius: 0.5,
                  ),
                ]
              : null,
        ),
        child: Text(
          symbol == AppConstants.nifty50
              ? 'NIFTY50'
              : (symbol == AppConstants.bankNifty
                  ? 'BANKNIFTY'
                  : (symbol == 'SENSEX'
                      ? 'SENSEX'
                      : (symbol == AppConstants.finNifty ? 'FINNIFTY' : (AppConstants.instrumentNames[symbol] ?? symbol)))),
          style: TextStyle(
            color: isSelected ? activeColor : AppTheme.subTextColor,
            fontSize: 9.5,
            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedInstrumentPillCard(
    String selectedInstrument,
    double animatedPrice,
    double referencePrice,
    bool isPositive,
  ) {
    final double change = animatedPrice - referencePrice;
    final double changePercent = referencePrice != 0 ? (change / referencePrice) * 100 : 0.0;
    final Color glowColor = isPositive ? AppTheme.bullColor : AppTheme.bearColor;
    
    // Resolve logo
    final cleanSymbol = StockLogos.cleanSymbol(selectedInstrument);
    Widget logoWidget;
    if (StockLogos.localAssets.containsKey(cleanSymbol)) {
      logoWidget = Image.asset(
        StockLogos.localAssets[cleanSymbol]!,
        fit: BoxFit.cover,
        width: 32,
        height: 32,
        errorBuilder: (context, error, stackTrace) => _buildDefaultInstrumentLogo(),
      );
    } else {
      logoWidget = _InstrumentLogoWithFallback(
        primaryUrl: StockLogos.getLogoUrl(cleanSymbol),
        fallbackUrl: StockLogos.getFallbackLogoUrl(cleanSymbol),
        size: 32,
        defaultWidget: _buildDefaultInstrumentLogo(),
      );
    }

    return Container(
      width: 380, // broad length!
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1524).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: glowColor.withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.15),
            blurRadius: 12,
            spreadRadius: 1.5,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 1. Logo & Name Group
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Individual stock logo icon
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: ClipOval(
                  child: logoWidget,
                ),
              ),
              const SizedBox(width: 12),
              
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppConstants.instrumentNames[selectedInstrument] ?? selectedInstrument,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      shadows: [
                        Shadow(
                          color: Colors.white24,
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'LIVE SCAN • ${intl.DateFormat('dd-MM-yyyy').format(DateTime.now())}',
                    style: TextStyle(
                      color: glowColor.withValues(alpha: 0.7),
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          // 2. Price Display Group
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '₹${animatedPrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'monospace',
                      shadows: [
                        Shadow(
                          color: Colors.white24,
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${isPositive ? "↑" : "↓"} ${isPositive ? "+" : ""}${change.toStringAsFixed(2)} (${isPositive ? "+" : ""}${changePercent.toStringAsFixed(2)}%)',
                    style: TextStyle(
                      color: glowColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'monospace',
                      shadows: [
                        Shadow(
                          color: glowColor.withValues(alpha: 0.4),
                          blurRadius: 6,
                        ),
                      ],
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

  Widget _buildDefaultInstrumentLogo() {
    return _buildSymbolMonogram('NSE', size: 32);
  }

  Widget _buildInstrumentGlowingBar(String selectedInstrument, bool isPositive) {
    final Color glowColor = isPositive ? AppTheme.bullColor : AppTheme.bearColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1524).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: glowColor.withValues(alpha: 0.15),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.04),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCompactInstrumentChip(AppConstants.nifty50, selectedInstrument == AppConstants.nifty50, glowColor),
          const SizedBox(width: 6),
          _buildCompactInstrumentChip(AppConstants.bankNifty, selectedInstrument == AppConstants.bankNifty, glowColor),
          const SizedBox(width: 6),
          _buildCompactInstrumentChip('SENSEX', selectedInstrument == 'SENSEX', glowColor),
          const SizedBox(width: 6),
          _buildCompactInstrumentChip(AppConstants.finNifty, selectedInstrument == AppConstants.finNifty, glowColor),
          if (selectedInstrument != AppConstants.nifty50 &&
              selectedInstrument != AppConstants.bankNifty &&
              selectedInstrument != 'SENSEX' &&
              selectedInstrument != AppConstants.finNifty) ...[
            const SizedBox(width: 6),
            _buildCompactInstrumentChip(selectedInstrument, true, glowColor),
          ],
        ],
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
          color: AppTheme.bearColor.withValues(alpha: 0.85),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off_rounded, color: Colors.white, size: 14),
              SizedBox(width: 8),
              Text(
                'OFFLINE — SHOWING CACHED DATA',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNewCandleBadge() {
    return Positioned(
      bottom: 110,
      right: 16,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _autoScroll = true;
            _newCandleAvailable = false;
          });
          _zoomPanBehavior.reset();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.primaryCyan,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 10,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: AppTheme.primaryCyan.withValues(alpha: 0.5),
                blurRadius: 12,
                spreadRadius: 2,
              )
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_downward_rounded, color: Colors.black, size: 14),
              SizedBox(width: 6),
              Text(
                'NEW CANDLE',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // News Ticker removed - transitioning to centralized notification system

  // Sentiment Gauge removed - using consolidated dashboard indicators



  PreferredSizeWidget _buildAppBar(String instrument, bool isSuperuser, bool isAdmin, double animatedPrice, bool isReplaying) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 600;
    final isTiny = screenWidth < 420;

    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1)),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    if (!isSuperuser && !isAdmin) return;
                    HapticFeedback.lightImpact();
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPanelScreen()));
                  },
                  onLongPress: () {
                    if (!isSuperuser && !isAdmin) return;
                    HapticFeedback.heavyImpact();
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPanelScreen()));
                  },
                  child: Hero(
                    tag: 'logo',
                    child: Container(
                      width: 32,
                      height: 32,
                      padding: const EdgeInsets.all(6), // Large padding to make the logo much smaller
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF202026), // Matches the dark background of the logo image
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1),
                      ),
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.contain, // Fits the entire logo (bull + text) inside the padded circle
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: AppTheme.cardColor,
                          child: const Icon(Icons.show_chart_rounded, color: AppTheme.primaryCyan, size: 16),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isTiny
                      ? 'ORDERFLOW'
                      : (isCompact ? 'ORDERFLOW ANALYZER' : 'MOST ADVANCE ORDERFLOW ANALYZER'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    color: AppTheme.goldColor,
                    fontSize: ((isTiny ? 8.0 : (isCompact ? 8.5 : 10.0)) * _scaleFactor).toDouble(),
                    fontWeight: FontWeight.w900,
                    letterSpacing: isCompact ? 0.2 : 1.0,
                    shadows: [
                      Shadow(
                        color: AppTheme.goldColor.withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.0),
                  decoration: BoxDecoration(
                    color: AppTheme.goldColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.goldColor.withValues(alpha: 0.4), width: 0.8),
                  ),
                  child: Text(
                    _getShortUid(),
                    style: TextStyle(
                      color: AppTheme.goldColor,
                      fontSize: (isCompact ? 8.0 : 9.0) * _scaleFactor,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                if (!isCompact) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.0),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryCyan.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.primaryCyan.withValues(alpha: 0.4), width: 0.8),
                    ),
                    child: Text(
                      intl.DateFormat('dd-MM-yyyy').format(DateTime.now()),
                      style: TextStyle(
                        color: AppTheme.primaryCyan,
                        fontSize: 8 * _scaleFactor,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      reverse: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [

                          _buildIconButton(
                            icon: Icons.campaign_rounded,
                            color: AppTheme.goldColor,
                            tooltip: 'Signal Radar',
                            isCompact: isCompact,
                            onPressed: () => _showSignalsBottomSheet(context),
                          ),
                          SizedBox(width: isCompact ? 4 : 6),
                          _buildIconButton(
                            icon: Icons.grid_view_rounded,
                            color: AppTheme.primaryCyan,
                            tooltip: 'Nifty 50 Heatmap',
                            isCompact: isCompact,
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const HeatmapScreen()),
                              );
                            },
                          ),
                          SizedBox(width: isCompact ? 4 : 6),
                          _buildIconButton(
                            icon: Icons.search_rounded,
                            color: AppTheme.primaryCyan,
                            tooltip: 'Search Stocks',
                            isCompact: isCompact,
                            onPressed: () => _openStockSearch(
                              isIndexOnly: ref.read(authProvider).user?.isIndexOnly ?? false,
                            ),
                          ),
                          SizedBox(width: isCompact ? 4 : 6),
                          _buildIconButton(
                            icon: Icons.person_rounded,
                            color: AppTheme.primaryCyan,
                            tooltip: 'User Profile',
                            isCompact: isCompact,
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const ProfileScreen()),
                              );
                            },
                          ),
                          SizedBox(width: isCompact ? 4 : 6),
                          if (_activePriceAlerts.isNotEmpty) ...[
                            _buildIconButton(
                              icon: Icons.notifications_off_rounded, 
                              color: AppTheme.goldColor,
                              isCompact: isCompact,
                              onPressed: () {
                                setState(() => _activePriceAlerts.clear());
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('All alerts cleared'), backgroundColor: AppTheme.cardColor)
                                );
                              }
                            ),
                            SizedBox(width: isCompact ? 4 : 6),
                          ],
                          if (isAdmin || isSuperuser) ...[
                            if (!isReplaying) ...[
                              _buildIconButton(
                                icon: Icons.history_toggle_off_rounded,
                                color: AppTheme.primaryCyan,
                                tooltip: 'Replay Candlesticks',
                                isCompact: isCompact,
                                onPressed: () => _selectReplayDate(context),
                              ),
                              SizedBox(width: isCompact ? 4 : 6),
                            ],
                            _buildIconButton(
                              icon: Icons.auto_awesome_rounded,
                              color: AppTheme.goldColor,
                              tooltip: 'Auto-Inject Day Swings (Promo)',
                              isCompact: isCompact,
                              onPressed: _handleAutoInjectDaySwings,
                            ),
                            SizedBox(width: isCompact ? 4 : 6),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon, 
    required Color color, 
    String? tooltip, 
    required VoidCallback onPressed,
    bool isCompact = false,
  }) {
    final size = isCompact ? 32.0 : 36.0;
    final iconSize = isCompact ? 16.0 : 18.0;

    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF1B1E28),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.35), width: 1.0),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.08),
                blurRadius: 4,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Icon(icon, color: color, size: iconSize),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(
        message: tooltip,
        child: button,
      );
    }
    return button;
  }

  Widget _buildInstrumentLogo(String symbol, {double size = 32}) {
    final cleanSymbol = StockLogos.cleanSymbol(symbol);

    // 1. If it's a local asset
    if (StockLogos.localAssets.containsKey(cleanSymbol)) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.05),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size / 2),
          child: Padding(
            padding: const EdgeInsets.all(2.0),
            child: Image.asset(
              StockLogos.localAssets[cleanSymbol]!,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => _buildFallbackGradientLogo(symbol, size),
            ),
          ),
        ),
      );
    }

    // 2. If it has a domain for network logo
    if (StockLogos.domains.containsKey(cleanSymbol)) {
      final logoUrl = StockLogos.getLogoUrl(cleanSymbol);
      final fallbackUrl = StockLogos.getFallbackLogoUrl(cleanSymbol);

      if (logoUrl.isNotEmpty) {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size / 2),
            child: Padding(
              padding: const EdgeInsets.all(2.0),
              child: Image.network(
                logoUrl,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Image.network(
                    fallbackUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => _buildFallbackGradientLogo(symbol, size),
                  );
                },
              ),
            ),
          ),
        );
      }
    }

    // Default fallback: Custom Gradient Logo
    return _buildFallbackGradientLogo(symbol, size);
  }

  Widget _buildFallbackGradientLogo(String symbol, double size) {
    Color startColor;
    Color endColor;
    String letter = symbol.isNotEmpty ? symbol[0].toUpperCase() : 'S';

    final clean = StockLogos.cleanSymbol(symbol);

    if (clean == 'NIFTY50') {
      startColor = const Color(0xFF00C6FF);
      endColor = const Color(0xFF0072FF);
      letter = 'N';
    } else if (clean == 'BANKNIFTY') {
      startColor = const Color(0xFF7F00FF);
      endColor = const Color(0xFFE100FF);
      letter = 'B';
    } else if (clean == 'FINNIFTY') {
      startColor = const Color(0xFF3A1C71);
      endColor = const Color(0xFFD76D77);
      letter = 'F';
    } else if (clean == 'MIDCAPNIFTY' || clean == 'MIDCPNIFTY') {
      startColor = const Color(0xFFFF512F);
      endColor = const Color(0xFFDD2476);
      letter = 'M';
    } else if (clean == 'SENSEX') {
      startColor = const Color(0xFFFF416C);
      endColor = const Color(0xFFFF4B2B);
      letter = 'S';
    } else if (clean == 'NIFTYIT') {
      startColor = const Color(0xFF11998E);
      endColor = const Color(0xFF38EF7D);
      letter = 'IT';
    } else if (clean == 'NIFTYAUTO') {
      startColor = const Color(0xFFF2994A);
      endColor = const Color(0xFFF2C94C);
      letter = 'A';
    } else if (clean == 'NIFTYMETAL') {
      startColor = const Color(0xFFBDC3C7);
      endColor = const Color(0xFF2C3E50);
      letter = 'M';
    } else if (clean == 'NIFTYPHARMA') {
      startColor = const Color(0xFF00B4DB);
      endColor = const Color(0xFF0083B0);
      letter = 'P';
    } else if (clean == 'NIFTYFMCG') {
      startColor = const Color(0xFFFF9966);
      endColor = const Color(0xFFFF5E62);
      letter = 'F';
    } else if (clean == 'NIFTYINFRA') {
      startColor = const Color(0xFFCAC531);
      endColor = const Color(0xFFF3F9A7);
      letter = 'IN';
    } else if (clean == 'NIFTYENERGY') {
      startColor = const Color(0xFFF3904F);
      endColor = const Color(0xFF3B4371);
      letter = 'E';
    } else if (clean == 'NIFTYMEDIA') {
      startColor = const Color(0xFFDA22FF);
      endColor = const Color(0xFF9733EE);
      letter = 'ME';
    } else if (clean == 'NIFTYREALTY') {
      startColor = const Color(0xFFE52D27);
      endColor = const Color(0xFFB31217);
      letter = 'R';
    } else if (clean == 'NIFTYPSE') {
      startColor = const Color(0xFF4568DC);
      endColor = const Color(0xFFB06AB8);
      letter = 'PS';
    } else {
      final hash = clean.hashCode;
      final hue1 = (hash % 360).toDouble();
      final hue2 = ((hash + 60) % 360).toDouble();
      startColor = HSLColor.fromAHSL(1.0, hue1, 0.85, 0.55).toColor();
      endColor = HSLColor.fromAHSL(1.0, hue2, 0.85, 0.45).toColor();
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [startColor, endColor],
        ),
        boxShadow: [
          BoxShadow(
            color: startColor.withValues(alpha: 0.3),
            blurRadius: 10,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * (letter.length > 1 ? 0.35 : 0.45),
            fontWeight: FontWeight.w900,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.3),
                offset: const Offset(0, 1),
                blurRadius: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstrumentSelector(String selected, bool isPositive) {
    final Color glowColor = isPositive ? AppTheme.bullColor : AppTheme.bearColor;
    final List<String> defaultSymbols = [
      AppConstants.nifty50,
      AppConstants.bankNifty,
      'SENSEX',
      AppConstants.finNifty,
    ];
    final bool isDefault = defaultSymbols.contains(selected);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: glowColor.withValues(alpha: 0.15)),
              boxShadow: [
                BoxShadow(
                  color: glowColor.withValues(alpha: 0.03),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              children: [
                _buildInstrumentChip(AppConstants.nifty50, selected == AppConstants.nifty50, glowColor),
                const SizedBox(width: 6),
                _buildInstrumentChip(AppConstants.bankNifty, selected == AppConstants.bankNifty, glowColor),
                const SizedBox(width: 6),
                _buildInstrumentChip('SENSEX', selected == 'SENSEX', glowColor),
                const SizedBox(width: 6),
                _buildInstrumentChip(AppConstants.finNifty, selected == AppConstants.finNifty, glowColor),
                if (!isDefault) ...[
                  const SizedBox(width: 6),
                  _buildInstrumentChip(selected, true, glowColor),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInstrumentChip(String symbol, bool isSelected, Color activeColor) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() {
            _autoScroll = true;
            _xVisibleMin = null;
            _xVisibleMax = null;
            _yVisibleMin = null;
            _yVisibleMax = null;
          });
          ref.read(selectedInstrumentProvider.notifier).state = symbol;
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? activeColor.withValues(alpha: 0.5) : Colors.transparent,
              width: 1,
            ),
            boxShadow: isSelected ? [
              BoxShadow(
                color: activeColor.withValues(alpha: 0.2),
                blurRadius: 8,
                spreadRadius: -1,
              )
            ] : [],
          ),
          child: Text(
            symbol == AppConstants.nifty50
                ? 'NIFTY 50'
                : (symbol == AppConstants.bankNifty
                    ? 'BANK NIFTY'
                    : (symbol == 'SENSEX'
                        ? 'SENSEX'
                        : (symbol == AppConstants.finNifty ? 'FIN NIFTY' : (AppConstants.instrumentNames[symbol] ?? symbol)))),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? activeColor : AppTheme.subTextColor,
              fontSize: (9.5 * _scaleFactor).toDouble(),
              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPriceHeader(
    String instrument,
    CandleModel candle, 
    double animatedPrice,
    double change, 
    double changePercent, 
    double openPrice,
    bool isPointsFromOpenPositive, {
    int? candleCount,
  }) {
    final isPositive = change >= 0;
    final changeColor = isPositive ? AppTheme.bullColor : AppTheme.bearColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: AppTheme.neonGlassDecoration(
              glowColor: changeColor,
              opacity: 0.02,
              borderRadius: BorderRadius.circular(12),
              borderWidth: 1.0,
            ),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: changeColor.withValues(alpha: 0.35),
                        blurRadius: 10,
                        spreadRadius: 1.5,
                      ),
                    ],
                  ),
                  child: _buildInstrumentLogo(instrument, size: 28 * _scaleFactor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          AppConstants.instrumentNames[instrument] ?? instrument,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13.5 * _scaleFactor,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.2,
                            overflow: TextOverflow.ellipsis,
                            shadows: [
                              Shadow(
                                color: changeColor.withValues(alpha: 0.8),
                                blurRadius: 8,
                              ),
                              Shadow(
                                color: changeColor.withValues(alpha: 0.4),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '₹${animatedPrice.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 13.5 * _scaleFactor,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              shadows: [
                                Shadow(color: changeColor.withValues(alpha: 0.8), blurRadius: 8),
                                Shadow(color: changeColor.withValues(alpha: 0.4), blurRadius: 16),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isPositive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                                color: changeColor,
                                size: 10 * _scaleFactor,
                              ),
                              Text(
                                '${isPositive ? '+' : ''}${change.toStringAsFixed(2)} (${changePercent.toStringAsFixed(2)}%)',
                                style: TextStyle(
                                  color: changeColor,
                                  fontSize: 9.5 * _scaleFactor,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _handleRefresh,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Icon(
                        Icons.refresh_rounded, 
                        color: Colors.white.withValues(alpha: 0.8),
                        size: 14 * _scaleFactor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernBadge({required String text, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 9 * _scaleFactor,
          letterSpacing: 0.5,
        ),
      ),
    );
  }




  void _animateReplayXAxis(double targetMin, double targetMax, int speed) {
    if (!mounted || _xAxisController == null) return;

    if (_targetReplayXMin == targetMin && _targetReplayXMax == targetMax) return;

    final double startMin = _replayXMinAnimation?.value ?? _xAxisController!.visibleMinimum ?? targetMin;
    final double startMax = _replayXMaxAnimation?.value ?? _xAxisController!.visibleMaximum ?? targetMax;

    _targetReplayXMin = targetMin;
    _targetReplayXMax = targetMax;

    _replayXAxisController?.dispose();
    _replayXAxisController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (1500 / speed * 0.85).round().clamp(150, 1200)),
    );

    _replayXMinAnimation = Tween<double>(begin: startMin, end: targetMin).animate(
      CurvedAnimation(parent: _replayXAxisController!, curve: Curves.easeInOutCubic),
    );
    _replayXMaxAnimation = Tween<double>(begin: startMax, end: targetMax).animate(
      CurvedAnimation(parent: _replayXAxisController!, curve: Curves.easeInOutCubic),
    );

    _replayXAxisController!.addListener(() {
      if (mounted && _xAxisController != null) {
        _xAxisController!.visibleMinimum = _replayXMinAnimation!.value;
        _xAxisController!.visibleMaximum = _replayXMaxAnimation!.value;
      }
    });

    _replayXAxisController!.forward();
  }

  void _updateVisibleYRange(List<CandleModel> candles, double minX, double maxX) {
    if (candles.isEmpty) return;
    final int sIdx = math.max(0, minX.floor()).clamp(0, candles.length);
    final int eIdx = math.min(candles.length, (maxX + 1.0).ceil()).clamp(0, candles.length);
    if (eIdx > sIdx) {
      final sub = candles.sublist(sIdx, eIdx);
      if (sub.isNotEmpty) {
        final double vMin = sub.map((c) => c.low.toDouble()).reduce(math.min);
        final double vMax = sub.map((c) => c.high.toDouble()).reduce(math.max);
        final double span = math.max(vMax - vMin, 6.0);
        _yVisibleMin = vMin - (span * 0.05);
        _yVisibleMax = vMax + (span * 0.05);
      }
    }
  }

  Widget _buildChart(List<CandleModel> candles, double animatedClose, bool isSuperuser, double sessionOpenPrice) {
    final isAdmin = ref.read(authProvider).user?.isAdmin ?? false;
    if (candles.length < 25) {
      final symbol = ref.read(selectedInstrumentProvider);
      final bootstrapped = ref.read(candleRepositoryProvider).generateBootstrapCandles(symbol, candles);
      if (bootstrapped.length > candles.length) {
        candles = bootstrapped;
      }
    }
    if (candles.isNotEmpty) {
      debugPrint('[_buildChart] Rendering ${candles.length} candles. Last close: ${candles.last.close}');
    }
    const bgColor = Color(0xFF050811);
    const gridColor = Color(0xFF1E222D);
    
    final double maxVolume = candles.isEmpty 
        ? 1000.0 
        : candles.map((c) => c.volume.toDouble()).reduce(math.max);
    final double volumeAxisMax = maxVolume == 0 ? 1000.0 : maxVolume * 4;

    // Build sequential index map for CategoryAxis (eliminates overnight gap)
    // Each candle gets a sequential integer index as its X value
    final Map<String, int> candleIndexMap = {};
    final List<String> axisLabels = [];
    String? prevDayKey;
    for (var i = 0; i < candles.length; i++) {
      final c = candles[i];
      final key = c.candleKey;
      candleIndexMap[key] = i;
      final dayKey = '${c.timeStart.year}-${c.timeStart.month}-${c.timeStart.day}';
      if (prevDayKey != null && prevDayKey != dayKey) {
        // First candle of a new session — show date label
        axisLabels.add(intl.DateFormat('dd MMM').format(c.timeStart));
      } else {
        axisLabels.add(intl.DateFormat('hh:mm').format(c.timeStart));
      }
      prevDayKey = dayKey;
    }

    // Calculate local viewport bounds safely without mutating State fields during render
    double? computedXMin = _xVisibleMin;
    double? computedXMax = _xVisibleMax;
    double? computedYMin = _yVisibleMin;
    double? computedYMax = _yVisibleMax;

    if (_autoScroll && candles.isNotEmpty) {
      final int targetVisibleCount = AppConstants.maxVisibleCandles;
      computedXMin = math.max(0.0, (candles.length - targetVisibleCount).toDouble());
      computedXMax = (candles.length - 1 + 0.8).toDouble();
      _yVisibleMin = null;
      _yVisibleMax = null;
    }

    // Auto-fit Y axis dynamically according to currently visible candles in viewport
    if (candles.isNotEmpty) {
      final double currentXMin = computedXMin ?? math.max(0.0, (candles.length - AppConstants.maxVisibleCandles).toDouble());
      final double currentXMax = computedXMax ?? (candles.length - 1 + 0.8);

      int startIdx = currentXMin.floor().clamp(0, candles.length - 1);
      int endIdx = currentXMax.ceil().clamp(0, candles.length - 1);
      if (startIdx > endIdx) {
        final tmp = startIdx;
        startIdx = endIdx;
        endIdx = tmp;
      }

      final visibleViewportCandles = candles.sublist(startIdx, endIdx + 1);
      if (visibleViewportCandles.isNotEmpty) {
        double vMin = visibleViewportCandles.map((c) => c.low.toDouble()).reduce(math.min);
        double vMax = visibleViewportCandles.map((c) => c.high.toDouble()).reduce(math.max);
        
        // Include last known price ONLY if live candle is currently in the visible viewport AND within proximity
        final bool isLiveVisible = (endIdx >= candles.length - 1);
        if (isLiveVisible && _lastKnownPrice > 0 && (_lastKnownPrice - vMax).abs() < 120 && (vMin - _lastKnownPrice).abs() < 120) {
          vMin = math.min(vMin, _lastKnownPrice);
          vMax = math.max(vMax, _lastKnownPrice);
        }

        final double rawSpan = vMax - vMin;
        final double span = math.max(rawSpan, 12.0);
        // Optimal 8% padding so visible candles fill 84% of chart height - big, clear & prominent!
        final double padding = span * 0.08;
        computedYMin = vMin - padding;
        computedYMax = vMax + padding;
      }
    }

    if (computedYMin != null && computedYMax != null) {
      computedYMin = (computedYMin / 5.0).floor() * 5.0;
      computedYMax = (computedYMax / 5.0).ceil() * 5.0;
    }

    final double currentVisibleSpan = (computedXMax != null && computedXMin != null)
        ? (computedXMax - computedXMin)
        : (candles.length > AppConstants.maxVisibleCandles ? (AppConstants.maxVisibleCandles + 2).toDouble() : candles.length.toDouble());
    final bool isZoomedOut = currentVisibleSpan > 35;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF050811),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              if (_chartHeight != constraints.maxHeight) {
                setState(() => _chartHeight = constraints.maxHeight);
              }
              if (_autoScroll && _xAxisController != null && computedXMin != null && computedXMax != null) {
                _xAxisController!.visibleMinimum = computedXMin;
                _xAxisController!.visibleMaximum = computedXMax;
              }
            }
          });
          
          return ValueListenableBuilder<double?>(
            valueListenable: _pendingAlertPriceNotifier,
            builder: (context, pendingPrice, _) {
              return Stack(
                children: [
                  ClipRect(
                    child: Listener(
                      onPointerSignal: (pointerSignal) {
                        if (pointerSignal is PointerScrollEvent) {
                          final double delta = pointerSignal.scrollDelta.dy;
                          if (delta != 0) {
                            _handleTrackpadZoom(delta > 0 ? 0.05 : -0.05, candles);
                          }
                        }
                      },
                      child: SfCartesianChart(
            key: ValueKey('chart_main_${ref.read(selectedInstrumentProvider)}'),
            margin: const EdgeInsets.fromLTRB(8, 12, 12, 35),
            backgroundColor: const Color(0xFF050811),
            plotAreaBackgroundColor: const Color(0xFF050811),
            plotAreaBorderWidth: 0,
            legend: const Legend(isVisible: false),

            // Sync with axis state changes
            onActualRangeChanged: (ActualRangeChangedArgs args) {
              if (args.axisName == 'primaryYAxis') {
                 _autoYMin = (args.visibleMin as num?)?.toDouble();
                 _autoYMax = (args.visibleMax as num?)?.toDouble();
              } else if (args.axisName == 'primaryXAxis') {
                 _xVisibleMin = (args.visibleMin as num?)?.toDouble();
                 _xVisibleMax = (args.visibleMax as num?)?.toDouble();
              }
            },
        
        // 1+2+4: Enhanced touch down — record time/position, schedule HUD
        onChartTouchInteractionDown: (ChartTouchInteractionArgs args) {
          _touchStartTime = DateTime.now();
          _touchStartPosition = args.position;
          // Schedule HUD show after 3s long-hold (Feature #2)
          _hudDismissTimer?.cancel();
          Future.delayed(const Duration(milliseconds: 3000), () {
            if (mounted && _touchStartTime != null && _touchStartPosition != null &&
                _seriesController != null && candles.isNotEmpty) {
              final elapsed = DateTime.now().difference(_touchStartTime!);
              if (elapsed.inMilliseconds >= 3000) {
                // still holding — resolve candle
                try {
                  final point = _seriesController!.pixelToPoint(_touchStartPosition!);
                  int index = -1;
                  if (point.x is num) {
                    index = (point.x as num).round().clamp(0, candles.length - 1);
                  } else if (point.x != null) {
                    final str = point.x.toString();
                    if (candleIndexMap.containsKey(str)) {
                      index = candleIndexMap[str]!;
                    } else {
                      final parsed = double.tryParse(str);
                      if (parsed != null) {
                        index = parsed.round().clamp(0, candles.length - 1);
                      }
                    }
                  }
                  final price = (point.y as num).toDouble();
                  if (index >= 0 && index < candles.length) {
                    HapticFeedback.selectionClick();
                    if (mounted) {
                      setState(() {
                        _hudCandle = candles[index];
                        if (isSuperuser || isAdmin) {
                          _longPressTargetCandle = candles[index];
                          _selectedCandleTime = candles[index].timeStart;
                          _longPressBubblePosition = _touchStartPosition;
                          _longPressPrice = price;
                        }
                      });
                    }
                    // Auto-dismiss HUD after 4s 
                    _hudDismissTimer = Timer(const Duration(seconds: 4), () {
                      if (mounted) {
                        setState(() {
                          _hudCandle = null;
                          _longPressTargetCandle = null;
                          _longPressBubblePosition = null;
                          _longPressPrice = null;
                        });
                      }
                    });
                  }
                } catch (_) {}
              }
            }
          });
        },
        
        onChartTouchInteractionMove: (ChartTouchInteractionArgs args) {
          if (_touchStartTime != null && _touchStartPosition != null) {
            final delta = (args.position - _touchStartPosition!).distance;
            
            // If finger moves more than 15 pixels, it's a pan/drag/zoom
            if (delta > 15) {
              _touchStartTime = null;
              _autoScroll = false;
              _hasUserZoomed = true;
              if (_hudCandle != null || _longPressBubblePosition != null) {
                _hudCandle = null;
                _longPressTargetCandle = null;
                _longPressBubblePosition = null;
                _longPressPrice = null;
              }
            } else {
              final duration = DateTime.now().difference(_touchStartTime!);
              
              // If held for 5 seconds, enter "adjust mode"
              if (duration.inMilliseconds > 5000 && _seriesController != null) {
                final point = _seriesController!.pixelToPoint(args.position);
                final price = point.y as num;
                
                _pendingAlertPriceNotifier.value = price.toDouble();
                // Haptic feedback to indicate "unlocked"
                if (_pendingAlertPriceNotifier.value != null && _touchStartTime != null) {
                   HapticFeedback.mediumImpact();
                   _touchStartTime = null; // Prevent re-triggering
                }
              }
            }
          }
          
          // Pending alert dragging
          if (_pendingAlertPriceNotifier.value != null && _seriesController != null) {
             final point = _seriesController!.pixelToPoint(args.position);
             final price = point.y as num;
             _pendingAlertPriceNotifier.value = _getSnappedPrice(price.toDouble(), candles);
          }
        },
        
        onTooltipRender: (TooltipArgs args) {
          // Format tooltip to show readable date instead of timestamp key
          if (args.pointIndex != null && args.pointIndex! >= 0 && args.pointIndex! < candles.length) {
             final date = candles[args.pointIndex!.toInt()].timeStart;
             args.text = intl.DateFormat('dd MMM hh:mm a').format(date);
          }
        },
        
        onChartTouchInteractionUp: (ChartTouchInteractionArgs args) {
          if (_pendingAlertPriceNotifier.value != null) {
             _showPriceAlertDialog(_pendingAlertPriceNotifier.value!);
             _pendingAlertPriceNotifier.value = null;
          } else if (_touchStartTime != null) {
            // 1. Double-tap detection: snap back to live
            final now = DateTime.now();
            final isDoubleTap = _lastTapTime != null &&
                now.difference(_lastTapTime!).inMilliseconds < 350;
            _lastTapTime = now;

            if (isDoubleTap) {
              HapticFeedback.mediumImpact();
              setState(() {
                _resetAutoZoomAndFit();
                _hudCandle = null;
              });
            } else if ((isSuperuser || isAdmin) && candles.isNotEmpty && _seriesController != null) {
              // Removed direct single-tap injection to rely entirely on the new long-press bubble context menu.
              // A single tap merely acknowledges the touch for navigation without opening the panel.
              HapticFeedback.lightImpact();
              if (_longPressBubblePosition != null) {
                setState(() {
                  _longPressBubblePosition = null;
                  _longPressTargetCandle = null;
                  _longPressPrice = null;
                });
              }
            }
          }
          _touchStartTime = null;
        },
        
        zoomPanBehavior: _zoomPanBehavior,

        onZoomStart: (ZoomPanArgs args) {
          if (_autoScroll) {
            _autoScroll = false;
          }
          if (!_hasUserZoomed) {
            _hasUserZoomed = true;
          }
        },

        // 5. Real-time frame-by-frame auto adjust & auto zoom feedback
        onZooming: (ZoomPanArgs args) {
          if (_autoScroll) {
            _autoScroll = false;
          }
          if (!_hasUserZoomed) {
            _hasUserZoomed = true;
          }
          final zoomFactor = args.currentZoomFactor;
          if (zoomFactor > 0) {
            _currentZoomFactor = zoomFactor;
            final totalCandles = candles.length;
            final visibleCandles = (totalCandles * zoomFactor).round().clamp(1, totalCandles);
            _zoomLabelNotifier.value = '$visibleCandles CANDLES';
            _zoomLabelTimer?.cancel();
            _zoomLabelTimer = Timer(const Duration(milliseconds: 1500), () {
              if (mounted) _zoomLabelNotifier.value = '';
            });
          }
          if (mounted) {
            setState(() {});
          }
        },

        onZoomReset: (ZoomPanArgs args) {
          if (mounted) {
            setState(() {
              _autoScroll = true;
              _hasUserZoomed = false;
            });
          }
        },

        onZoomEnd: (ZoomPanArgs args) {
          if (mounted) {
            setState(() {});
          }
        },

        trackballBehavior: TrackballBehavior(
          enable: true,
          activationMode: ActivationMode.singleTap,
          tooltipDisplayMode: TrackballDisplayMode.groupAllPoints,
          lineType: TrackballLineType.vertical,
          lineColor: Colors.white.withValues(alpha: 0.2),
          lineWidth: 0.5,
          lineDashArray: const [4, 4],
          markerSettings: const TrackballMarkerSettings(markerVisibility: TrackballVisibilityMode.visible),
          tooltipSettings: const InteractiveTooltip(
            enable: true,
            color: AppTheme.cardColor,
            textStyle: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w900),
          ),
        ),
        
        crosshairBehavior: CrosshairBehavior(
          enable: true,
          activationMode: ActivationMode.singleTap,
          lineType: CrosshairLineType.both,
          lineColor: Colors.white.withValues(alpha: 0.2),
          lineWidth: 0.5,
          lineDashArray: const [4, 4],
        ),
        
        primaryXAxis: CategoryAxis(
          name: 'primaryXAxis',
          plotOffsetEnd: 0.0, // Zero empty space right up to last candlestick
          onRendererCreated: (CategoryAxisController controller) {
            _xAxisController = controller;
          },
          majorGridLines: const MajorGridLines(width: 0.5, color: Color(0xFF2A2E39)),
          axisLine: const AxisLine(width: 0),
          labelStyle: const TextStyle(color: AppTheme.dimTextColor, fontSize: 10, fontWeight: FontWeight.bold),
          majorTickLines: const MajorTickLines(size: 0),
          edgeLabelPlacement: EdgeLabelPlacement.shift,
          labelIntersectAction: AxisLabelIntersectAction.hide,
          initialVisibleMinimum: computedXMin,
          initialVisibleMaximum: computedXMax,
          plotBands: [
            if (_selectedCandleTime != null && candles.any((c) => (c.timeStart.millisecondsSinceEpoch - _selectedCandleTime!.millisecondsSinceEpoch).abs() < 5 * 60 * 1000))
              PlotBand(
                start: candles.firstWhere((c) => (c.timeStart.millisecondsSinceEpoch - _selectedCandleTime!.millisecondsSinceEpoch).abs() < 5 * 60 * 1000).candleKey,
                end: candles.firstWhere((c) => (c.timeStart.millisecondsSinceEpoch - _selectedCandleTime!.millisecondsSinceEpoch).abs() < 5 * 60 * 1000).candleKey,
                color: AppTheme.primaryCyan.withValues(alpha: 0.15),
                borderColor: AppTheme.primaryCyan.withValues(alpha: 0.3),
                borderWidth: 1,
              ),
            // Highlight injected admin candles dynamically with glowing vertical columns
            ...candles.where((c) {
              final String? activeKey = _findActiveOrderflowKey(c);
              if (activeKey == null) return false;
              final data = orderflowData[activeKey]!;
              final injectedBy = data['injectedBy'] as String?;
              return injectedBy != null && injectedBy.isNotEmpty;
            }).map((c) {
              final String? activeKey = _findActiveOrderflowKey(c) ?? c.candleKey;
              final data = orderflowData[activeKey]!;
              final int buy = _parseNum(data['buyerCount']).toInt();
              final int sell = _parseNum(data['sellerCount']).toInt();
              final isBuyer = buy > sell;
              final baseColor = isBuyer ? const Color(0xFF00FF41) : const Color(0xFFFF003C);
              return PlotBand(
                start: c.candleKey,
                end: c.candleKey,
                color: baseColor.withValues(alpha: 0.08), // Subtle column glow
                borderColor: baseColor.withValues(alpha: 0.35),
                borderWidth: 1.2,
                shouldRenderAboveSeries: false, // Render under candles for premium design
              );
            }),
          ],
          interactiveTooltip: const InteractiveTooltip(
            enable: true,
            color: AppTheme.primaryCyan,
            textStyle: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900),
          ),
          axisLabelFormatter: (AxisLabelRenderDetails details) {
            // Primary: use sequential index to look up pre-built label
            int index = details.value.round();
            if (index >= 0 && index < axisLabels.length) {
              return ChartAxisLabel(axisLabels[index], details.textStyle);
            }
            // Fallback: details.text may contain the raw candleKey (timestamp ms string)
            // Parse it and format as hh:mm a so users never see raw epoch numbers
            final rawText = details.text;
            if (rawText.isNotEmpty) {
              String cleanText = rawText.contains('_') ? rawText.split('_').last : rawText;
              cleanText = cleanText.replaceAll(',', '').trim();
              int? ms = int.tryParse(cleanText);
              if (ms != null && ms > 0) {
                if (ms < 10000000000) ms *= 1000;
                final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
                return ChartAxisLabel(
                  intl.DateFormat('hh:mm').format(dt),
                  details.textStyle,
                );
              }
            }
            return ChartAxisLabel('', details.textStyle);
          },
        ),
        
        primaryYAxis: NumericAxis(
          name: 'primaryYAxis',
          minimum: computedYMin,
          maximum: computedYMax,
          desiredIntervals: 7, // Dynamic clean label intervals automatically adapted to price span
          anchorRangeToVisiblePoints: true, // AUTO-SCALE TO VISIBLE CANDLES
          opposedPosition: true,
          majorGridLines: const MajorGridLines(width: 0.5, color: Color(0xFF2A2E39)),
          minorGridLines: const MinorGridLines(width: 0),
          axisLine: const AxisLine(width: 0),
          plotBands: _activePriceAlerts.map((price) => PlotBand(
            start: price,
            end: price,
            shouldRenderAboveSeries: true,
            borderColor: AppTheme.goldColor.withValues(alpha: 0.4),
            borderWidth: 1,
            dashArray: const <double>[5, 5],
            text: 'ALERT: ${price.toStringAsFixed(0)}',
            textStyle: const TextStyle(color: AppTheme.goldColor, fontSize: 8, fontWeight: FontWeight.bold),
            horizontalTextAlignment: TextAnchor.start,
            verticalTextAlignment: TextAnchor.end,
          )).toList()
          ..addAll(pendingPrice != null ? [
            PlotBand(
              start: pendingPrice,
              end: pendingPrice,
              shouldRenderAboveSeries: true,
              borderColor: AppTheme.bullColor,
              borderWidth: 2,
              text: 'SNAP: ${pendingPrice.toStringAsFixed(0)}',
              textStyle: const TextStyle(color: AppTheme.bullColor, fontSize: 10, fontWeight: FontWeight.w900),
              horizontalTextAlignment: TextAnchor.end,
              verticalTextAlignment: TextAnchor.start,
            )
          ] : [])
          ..addAll(candles.isNotEmpty ? () {
            final double livePrice = animatedClose == 0 ? candles.last.close.toDouble() : animatedClose;
            final bool isBull = livePrice >= candles.last.open;
            final Color liveColor = isBull ? const Color(0xFF26A69A) : const Color(0xFFEF5350);
            return [
              PlotBand(
                start: livePrice,
                end: livePrice,
                shouldRenderAboveSeries: true,
                borderColor: liveColor.withValues(alpha: 0.85),
                borderWidth: 1.2,
                dashArray: const <double>[4, 3],
              )
            ];
          }() : []),
          numberFormat: intl.NumberFormat('#,##0'),
          labelStyle: const TextStyle(color: AppTheme.dimTextColor, fontSize: 10, fontWeight: FontWeight.bold),
          majorTickLines: const MajorTickLines(size: 0),
          tickPosition: TickPosition.inside,
          decimalPlaces: 0,
          interactiveTooltip: const InteractiveTooltip(
            enable: true,
            color: AppTheme.goldColor,
            textStyle: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900),
          ),
        ),

        axes: <ChartAxis>[
          NumericAxis(
            name: 'volumeYAxis',
            opposedPosition: false,
            isVisible: false,
            minimum: 0,
            maximum: isZoomedOut ? 1.0 : volumeAxisMax,
          )
        ],
        
        series: <CartesianSeries<dynamic, String>>[
          ColumnSeries<CandleModel, String>(
            name: 'Volume',
            dataSource: candles,
            xValueMapper: (CandleModel c, _) => c.candleKey,
            yValueMapper: (CandleModel c, int index) {
              if (isZoomedOut) return 0.0;
              final bool isLast = (index == candles.length - 1);
              final nowIST = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
              final bool isOngoing = isLast && (!c.isClosed && nowIST.isBefore(c.timeEnd));
              if (isOngoing) return 0.0;
              return c.volume.toDouble();
            },
            yAxisName: 'volumeYAxis',
            pointColorMapper: (CandleModel c, int index) {
              final bool isLast = (index == candles.length - 1);
              final nowIST = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
              final bool isOngoing = isLast && (!c.isClosed && nowIST.isBefore(c.timeEnd));
              if (isOngoing) return Colors.transparent;
              return c.close >= c.open 
                  ? AppTheme.bullColor.withValues(alpha: 0.15) 
                  : AppTheme.bearColor.withValues(alpha: 0.15);
            },
            animationDuration: 0,
            spacing: 0.2, 
          ),
          // Candles
          CandleSeries<CandleModel, String>(
            onRendererCreated: (ChartSeriesController controller) => _seriesController = controller,
            dataSource: candles.isEmpty ? [] : [
              ...candles.sublist(0, candles.length - 1),
              candles.last.copyWith(
                close: (ref.read(candleStreamProvider).isReplaying || _animatedCloseNotifier.value == 0)
                    ? candles.last.close 
                    : _animatedCloseNotifier.value
              ),
            ],
            xValueMapper: (CandleModel c, _) => c.candleKey,
            lowValueMapper: (CandleModel c, _) {
              final double h = c.high.toDouble();
              final double l = c.low.toDouble();
              if (h - l < 1.0) {
                final double mid = (h + l) / 2;
                return mid - 0.5;
              }
              return l;
            },
            highValueMapper: (CandleModel c, _) {
              final double h = c.high.toDouble();
              final double l = c.low.toDouble();
              if (h - l < 1.0) {
                final double mid = (h + l) / 2;
                return mid + 0.5;
              }
              return h;
            },
            openValueMapper: (CandleModel c, _) => c.open,
            closeValueMapper: (CandleModel c, _) {
              final double o = c.open.toDouble();
              final double cl = c.close.toDouble();
              if ((o - cl).abs() < 0.6) {
                return cl >= o ? o + 0.6 : o - 0.6;
              }
              return cl;
            },
            bullColor: AppTheme.bullColor,
            bearColor: AppTheme.bearColor,
            enableSolidCandles: true,
            borderWidth: ((_xVisibleMax != null && _xVisibleMin != null && (_xVisibleMax! - _xVisibleMin!) > 35) ? 0.7 : 1.2),
            width: 0.85,
            animationDuration: 0,
            spacing: 0.05, 
          ),
        ],

        // Orderflow annotations (green/red balls) + Live Pulse + Watermark
        annotations: [
          ..._buildOrderflowAnnotations(candles, candleIndexMap, isSuperuser || isAdmin),
          if (candles.isNotEmpty)
            CartesianChartAnnotation(
              widget: LiveCandlePulse(
                color: candles.last.close > candles.last.open 
                    ? AppTheme.bullColor 
                    : AppTheme.bearColor
              ),
              coordinateUnit: CoordinateUnit.point,
              x: candles.isNotEmpty ? candles.last.candleKey : '',
              y: animatedClose,
              verticalAlignment: ChartAlignment.center,
              horizontalAlignment: ChartAlignment.center,
            ),
          if (candles.isNotEmpty)
            CartesianChartAnnotation(
              widget: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: (animatedClose == 0 ? candles.last.close : animatedClose) >= candles.last.open
                      ? const Color(0xFF26A69A)
                      : const Color(0xFFEF5350),
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: [
                    BoxShadow(
                      color: ((animatedClose == 0 ? candles.last.close : animatedClose) >= candles.last.open
                          ? const Color(0xFF26A69A)
                          : const Color(0xFFEF5350)).withValues(alpha: 0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Text(
                  (animatedClose == 0 ? candles.last.close : animatedClose).toStringAsFixed(2),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              coordinateUnit: CoordinateUnit.point,
              x: candles.isNotEmpty ? candles.last.candleKey : '',
              y: animatedClose == 0 ? candles.last.close : animatedClose,
              verticalAlignment: ChartAlignment.center,
              horizontalAlignment: ChartAlignment.far,
            ),
        ],
      ),
    ),
  ),
      
      // Price Axis Gesture Handler (Right Side)
      Positioned(
        right: 0,
        top: 0,
        bottom: 35, // Match chart margin
        width: 55, // Touch target for vertical graph scrolling
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onScaleStart: (details) {
             _autoScroll = false;
             if (_yVisibleMin == null || _yVisibleMax == null) {
                if (candles.isNotEmpty) {
                   final int targetVisibleCount = AppConstants.maxVisibleCandles;
                   final int startIndex = math.max(0, candles.length - targetVisibleCount);
                   final viewportCandles = candles.sublist(startIndex);
                   if (viewportCandles.isNotEmpty) {
                      final double vMin = viewportCandles.map((c) => c.low.toDouble()).reduce(math.min);
                      final double vMax = viewportCandles.map((c) => c.high.toDouble()).reduce(math.max);
                      final double span = math.max(vMax - vMin, 6.0);
                      _yVisibleMin = vMin - (span * 0.10);
                      _yVisibleMax = vMax + (span * 0.10);
                   }
                }
             }
             if (_yVisibleMin != null && _yVisibleMax != null) {
                _initialRange = _yVisibleMax! - _yVisibleMin!;
                _initialMid = (_yVisibleMax! + _yVisibleMin!) / 2;
             }
          },
          onScaleUpdate: (details) {
            if (_seriesController == null || _yVisibleMin == null || _yVisibleMax == null) return;
            
            try {
               final point1 = _seriesController!.pixelToPoint(const Offset(0, 100));
               final point2 = _seriesController!.pixelToPoint(const Offset(0, 200));
               final num y1 = point1.y as num;
               final num y2 = point2.y as num;
               double pricePerPixel = (y1 - y2).abs() / 100;
               
               if (pricePerPixel == 0 || pricePerPixel.isNaN) {
                 final range = _yVisibleMax! - _yVisibleMin!;
                 pricePerPixel = range / 500;
               }

               if (details.scale == 1.0) {
                 // Drag Whole Graph UP and DOWN
                 final deltaPrice = details.focalPointDelta.dy * pricePerPixel;
                 setState(() {
                    _yVisibleMin = _yVisibleMin! + deltaPrice;
                    _yVisibleMax = _yVisibleMax! + deltaPrice;
                 });
               } else {
                 // Two Finger Vertical Stretch / Compress
                 final double rawRange = _initialRange / details.scale;
                 final double newRange = math.max(rawRange, 15.0); // Clamp minimum price span to 15.0 points
                 setState(() {
                    _yVisibleMin = _initialMid - (newRange / 2);
                    _yVisibleMax = _initialMid + (newRange / 2);
                 });
               }
            } catch (e) {
               // ignore
            }
          },
          onDoubleTap: () {
             setState(() {
               _resetAutoZoomAndFit();
             });
          },
        ),
      ),

      // Time Axis Scratch & Zoom Gesture Handler (Bottom Side)
      Positioned(
        left: 0,
        right: 50,
        bottom: 0,
        height: 45,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onScaleStart: (details) {
            _pinchStartMin = _xVisibleMin ?? math.max(0.0, (candles.length - AppConstants.maxVisibleCandles).toDouble());
            _pinchStartMax = _xVisibleMax ?? (candles.length - 1 + 0.8);
            _lastFocalPoint = details.focalPoint;
          },
          onScaleUpdate: (details) {
            if (_pinchStartMin == null || _pinchStartMax == null || candles.isEmpty) return;
            _autoScroll = false;

            final double initialSpan = _pinchStartMax! - _pinchStartMin!;
            final double chartWidth = math.max(MediaQuery.of(context).size.width - 60.0, 100.0);

            // Two-Finger Pinch Zooming on Time Axis
            if (details.scale != 1.0 && (details.scale - 1.0).abs() > 0.01) {
              final double scaleFactor = details.scale.clamp(0.2, 5.0);
              final double newSpan = (initialSpan / scaleFactor).clamp(8.0, candles.length.toDouble() + 5.0); // min 8 candles visible limit
              final double mid = (_pinchStartMin! + _pinchStartMax!) / 2.0;

              double newMin = mid - (newSpan / 2.0);
              double newMax = mid + (newSpan / 2.0);

              if (newMin < -1.0) newMin = -1.0;
              if (newMax > candles.length + 2.0) newMax = (candles.length + 2.0).toDouble();

              _xVisibleMin = newMin;
              _xVisibleMax = newMax;
              if (_xAxisController != null) {
                _xAxisController!.visibleMinimum = newMin;
                _xAxisController!.visibleMaximum = newMax;
              }
              setState(() {});
            }
            // One-Finger Horizontal Scratching (Dragging left/right to scale/pan time axis)
            else if (_lastFocalPoint != null) {
              final double deltaX = details.focalPoint.dx - _lastFocalPoint!.dx;
              if (deltaX.abs() > 0.2) {
                final double candleShift = (-deltaX / chartWidth) * initialSpan;

                double newMin = (_xVisibleMin ?? _pinchStartMin!) + candleShift;
                double newMax = (_xVisibleMax ?? _pinchStartMax!) + candleShift;

                if (newMin < -1.0) {
                  newMin = -1.0;
                  newMax = newMin + initialSpan;
                }
                if (newMax > candles.length + 2.0) {
                  newMax = (candles.length + 2.0).toDouble();
                  newMin = math.max(-1.0, newMax - initialSpan);
                }

                _xVisibleMin = newMin;
                _xVisibleMax = newMax;
                if (_xAxisController != null) {
                  _xAxisController!.visibleMinimum = newMin;
                  _xAxisController!.visibleMaximum = newMax;
                }
                setState(() {});
              }
            }

            _lastFocalPoint = details.focalPoint;
          },
          onScaleEnd: (_) {
            _lastFocalPoint = null;
            _pinchStartMin = null;
            _pinchStartMax = null;
          },
        ),
      ),
      // AUTO FIT / RESET ZOOM BUTTON — appears when user pans or zooms
      if (!_autoScroll || _hasUserZoomed)
        Positioned(
          bottom: 50,
          right: 56,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              setState(() {
                _resetAutoZoomAndFit();
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.primaryCyan.withValues(alpha: 0.6), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryCyan.withValues(alpha: 0.25),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.center_focus_strong_rounded, color: AppTheme.primaryCyan, size: 14),
                  SizedBox(width: 6),
                  Text(
                    'AUTO FIT',
                    style: TextStyle(
                      color: AppTheme.primaryCyan,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      // 2. CANDLE OHLC HUD — appears on 600ms long-press
      if (_hudCandle != null)
        Positioned(
          top: 12,
          left: 8,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _hudCandle != null ? 1.0 : 0.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117).withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primaryCyan.withValues(alpha: 0.3), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryCyan.withValues(alpha: 0.15),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    intl.DateFormat('dd MMM  hh:mm a').format(_hudCandle!.timeStart),
                    style: const TextStyle(
                      color: AppTheme.primaryCyan, fontSize: 9,
                      fontWeight: FontWeight.w900, letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildHudRow('O', _hudCandle!.open.toStringAsFixed(0), Colors.white70),
                  _buildHudRow('H', _hudCandle!.high.toStringAsFixed(0), AppTheme.bullColor),
                  _buildHudRow('L', _hudCandle!.low.toStringAsFixed(0), AppTheme.bearColor),
                  _buildHudRow('C', _hudCandle!.close.toStringAsFixed(0),
                    _hudCandle!.close >= _hudCandle!.open ? AppTheme.bullColor : AppTheme.bearColor),
                  _buildHudRow('Δ',
                    '${(_hudCandle!.close - _hudCandle!.open >= 0 ? '+' : '')}${(_hudCandle!.close - _hudCandle!.open).toStringAsFixed(0)}',
                    _hudCandle!.close >= _hudCandle!.open ? AppTheme.bullColor : AppTheme.bearColor),
                  _buildHudRow('V', _hudCandle!.volume.toString(), Colors.white70),
                ],
              ),
            ),
          ),
        ),

      // 3. Admin Long-Press Injection Bubble
      if ((isSuperuser || isAdmin) && _longPressBubblePosition != null && _longPressTargetCandle != null)
        Positioned(
          left: (_longPressBubblePosition!.dx - 60).clamp(0.0, MediaQuery.of(context).size.width - 150),
          top: (_longPressBubblePosition!.dy - 60).clamp(0.0, MediaQuery.of(context).size.height - 150),
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _selectedCandleTime = _longPressTargetCandle!.timeStart;
                _showOrderflowInput = true;

                if (_longPressPrice != null) {
                  _priceLevelController.text = _longPressPrice!.toStringAsFixed(1);
                  _ghostTriggerController.text = _longPressPrice!.toStringAsFixed(1);
                  _isGhostMode = true; // Auto-enable Ghost Mode for price levels
                }

                if (_isGhostMode && ref.read(selectedInstrumentProvider) == 'NIFTY50' && _suggestedSimilarStocks.isEmpty && !_isScanningSimilarPatterns) {
                  _startSimilarPatternScan();
                }

                final activeKey = _findActiveOrderflowKey(_longPressTargetCandle!);
                if (activeKey != null) {
                  _buyerController.text = orderflowData[activeKey]!['buyerCount']?.toString() ?? '';
                  _sellerController.text = orderflowData[activeKey]!['sellerCount']?.toString() ?? '';
                  _isInstitutionalSelected = orderflowData[activeKey]!['isInstitutional'] ?? false;
                  _isBigSignalSelected = orderflowData[activeKey]!['isBigSignal'] ?? false;
                  _isAdminOnlySelected = orderflowData[activeKey]!['adminOnly'] ?? false;
                  _isTrapSelected = orderflowData[activeKey]!['isTrap'] ?? false;
                  _isLiquidationSelected = orderflowData[activeKey]!['isLiquidation'] ?? false;
                  _selectedBubbleScale = (orderflowData[activeKey]!['bubbleScale'] as num?)?.toDouble() ?? 5.0;
                  _selectedPulseSpeed = (orderflowData[activeKey]!['pulseSpeed'] as num?)?.toDouble() ?? 1.0;
                  _selectedBubbleOpacity = (orderflowData[activeKey]!['bubbleOpacity'] as num?)?.toDouble() ?? 0.65;
                } else {
                  _buyerController.clear();
                  _sellerController.clear();
                  _isInstitutionalSelected = false;
                  _isBigSignalSelected = false;
                  _isAdminOnlySelected = false;
                  _isTrapSelected = false;
                  _isLiquidationSelected = false;
                  _selectedBubbleScale = 5.0;
                  _selectedPulseSpeed = 1.0;
                  _selectedBubbleOpacity = 0.65;
                }

                _longPressBubblePosition = null;
                _longPressTargetCandle = null;
                _longPressPrice = null;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primaryCyan,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(color: AppTheme.primaryCyan.withValues(alpha: 0.5), blurRadius: 15, spreadRadius: 2),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_circle_outline, color: Colors.black, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    _longPressPrice != null
                        ? 'INJECT AT ₹${_longPressPrice!.toStringAsFixed(1)}'
                        : 'INJECT HERE',
                    style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
          ),
        ),

      // 5. Zoom level label — flashes briefly when pinch-zooming
      Positioned(
        top: 12,
        right: 8,
        child: ValueListenableBuilder<String>(
          valueListenable: _zoomLabelNotifier,
          builder: (context, label, _) => AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: label.isNotEmpty ? 1.0 : 0.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.cardColor.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.primaryCyan.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.search_rounded, color: AppTheme.primaryCyan, size: 11),
                  const SizedBox(width: 5),
                  Text(label,
                    style: const TextStyle(
                      color: AppTheme.primaryCyan, fontSize: 10,
                      fontWeight: FontWeight.w900, letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),

      // Floating Zoom Controls (+ / -)
      Positioned(
        bottom: 80,
        right: 12,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F1420).withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _autoScroll = false;
                  final double currentMax = _xVisibleMax ?? (candles.length - 1 + 0.8);
                  final double currentMin = _xVisibleMin ?? math.max(0.0, currentMax - AppConstants.maxVisibleCandles);
                  final double currentSpan = math.max(currentMax - currentMin, 3.0);
                  final double newSpan = math.max(3.0, currentSpan * 0.65);
                  final double newMin = currentMax - newSpan;

                  _xVisibleMin = newMin;
                  _xVisibleMax = currentMax;
                  if (_xAxisController != null) {
                    _xAxisController!.visibleMinimum = newMin;
                    _xAxisController!.visibleMaximum = currentMax;
                  }
                  setState(() {});
                },
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.add_rounded, color: AppTheme.primaryCyan, size: 18),
                ),
              ),
              Container(width: 20, height: 1, color: Colors.white.withValues(alpha: 0.12)),
              InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _autoScroll = false;
                  final double currentMax = _xVisibleMax ?? (candles.length - 1 + 0.8);
                  final double currentMin = _xVisibleMin ?? math.max(0.0, currentMax - AppConstants.maxVisibleCandles);
                  final double currentSpan = math.max(currentMax - currentMin, 3.0);
                  final double newSpan = math.min(candles.length.toDouble() + 5.0, currentSpan * 1.5);
                  final double newMin = math.max(-1.0, currentMax - newSpan);

                  _xVisibleMin = newMin;
                  _xVisibleMax = currentMax;
                  if (_xAxisController != null) {
                    _xAxisController!.visibleMinimum = newMin;
                    _xAxisController!.visibleMaximum = currentMax;
                  }
                  setState(() {});
                },
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.remove_rounded, color: AppTheme.primaryCyan, size: 18),
                ),
              ),
            ],
          ),
        ),
      ),


      if (MediaQuery.of(context).size.width > 900)
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: Center(
            child: ValueListenableBuilder<double>(
              valueListenable: _animatedCloseNotifier,
              builder: (context, animatedClose, _) {
                final double open = sessionOpenPrice;
                final double close = animatedClose;
                final double change = close - open;
                final bool isPositive = change >= 0;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSelectedInstrumentPillCard(
                      ref.read(selectedInstrumentProvider),
                      animatedClose,
                      sessionOpenPrice,
                      isPositive,
                    ),
                    const SizedBox(width: 12),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _openStockSearch(isIndexOnly: false),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F1524).withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.primaryCyan.withValues(alpha: 0.25),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryCyan.withValues(alpha: 0.15),
                                blurRadius: 12,
                                spreadRadius: 1.5,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.search_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),

            ],
          ); // Stack
        }, // ValueListenableBuilder builder
      ); // ValueListenableBuilder
    }, // LayoutBuilder builder
  ), // LayoutBuilder
); // Container
  }

  Widget _buildHudRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            child: Text(label,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 8),
          Text(value,
            style: TextStyle(color: valueColor, fontSize: 11, fontWeight: FontWeight.w900, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  String? _findActiveOrderflowKey(Candle candle) {
    final String tsKey = candle.timeStart.millisecondsSinceEpoch.toString();
    final String candleKey = candle.candleKey;
    if (orderflowData.containsKey(tsKey)) return tsKey;
    if (orderflowData.containsKey(candleKey)) return candleKey;
    
    // Exact timestamp match (handling prefixed keys like "SYMBOL_TIMESTAMP")
    final candleMs = candle.timeStart.millisecondsSinceEpoch;
    for (final entryKey in orderflowData.keys) {
      final part = entryKey.contains('_') ? entryKey.split('_').last : entryKey;
      final entryTime = int.tryParse(part);
      if (entryTime != null && entryTime > 0) {
        final actualMs = entryTime < 10000000000 ? entryTime * 1000 : entryTime;
        if (actualMs == candleMs) {
          return entryKey;
        }
      }
    }
    
    // 5-minute bucket fallback (exact interval match within 5 minutes)
    for (final entryKey in orderflowData.keys) {
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

  List<CartesianChartAnnotation> _buildOrderflowAnnotations(List<CandleModel> candles, Map<String, int> candleIndexMap, bool isSuperuser) {
    final backgroundAnnotations = <CartesianChartAnnotation>[];
    final foregroundAnnotations = <CartesianChartAnnotation>[];
    int? spikeStartTimeMs;
    final symbol = ref.read(selectedInstrumentProvider);

    final double visibleCandlesCount;
    if (_xVisibleMin != null && _xVisibleMax != null) {
      visibleCandlesCount = _xVisibleMax! - _xVisibleMin!;
    } else if (candles.length > AppConstants.maxVisibleCandles) {
      // Defaults to maxVisibleCandles when first loaded
      visibleCandlesCount = (AppConstants.maxVisibleCandles + 2).toDouble();
    } else {
      visibleCandlesCount = candles.length.toDouble();
    }
    final bool isZoomedOut = visibleCandlesCount > 35;
    const double pillScale = 0.95;
    const bool shouldShowLabel = true;

    final isBankNifty = symbol.contains('BANKNIFTY');
    final spikeThreshold = isBankNifty ? 50.0 : 20.0;

    // FAST EXECUTION: Only process visible candles to minimize CPU usage
    // Determine visible window (last ~60 candles or full list if smaller)
    final int totalCandles = candles.length;
    // FAST EXECUTION: Only process to cached limit (usually 600)
    final int visibleStart = (totalCandles - 600).clamp(0, totalCandles);
    final visibleCandles = candles.sublist(visibleStart);

    for (final candle in visibleCandles) {
      if (!candleIndexMap.containsKey(candle.candleKey)) continue;

      final int candleIdx = candleIndexMap[candle.candleKey]!;
      if (_xVisibleMin != null && _xVisibleMax != null) {
        if (candleIdx < _xVisibleMin! - 1.5 || candleIdx > _xVisibleMax! + 1.5) continue;
      }

      final String? activeKey = _findActiveOrderflowKey(candle);
      final range = (candle.high - candle.low).abs();
      final isGreen = candle.close >= candle.open;
      
      int buyerCount = 0;
      int sellerCount = 0;
      bool isInstitutional = false;
      bool isHeavy = false;
      bool isBigSignal = false;
      bool isTrap = false;
      bool isLiquidation = false;
      bool hasAdminData = false;
      double rangeFactor = 1.0;

      // Default look
      double adminOpacity = 0.65;
      double adminGlow = 0.0;
      bool adminShowLabel = true;
      String adminTag = "";
      double adminPulseSpeed = 1.0;

      // 1. Check for Admin Data in Firestore
      if (activeKey != null) {
        final data = orderflowData[activeKey]!;
        final expiryTime = _parseNum(data['expiryTime']).toInt();
        if (expiryTime > 0 && DateTime.now().millisecondsSinceEpoch > expiryTime) {
          // Skip expired data
        } else {
          // STRICT CHECK: Only data manually injected by admin (has 'injectedBy') should glow
          // This prevents automated/legacy data from triggering the admin glow effect
          final injectedBy = data['injectedBy'] as String?;
          hasAdminData = injectedBy != null && injectedBy.isNotEmpty;
          
          num safeParse(dynamic val) {
             if (val is num) return val;
             if (val is String) return num.tryParse(val) ?? 0;
             return 0;
          }

          buyerCount = safeParse(data['buyerCount']).toInt();
          sellerCount = safeParse(data['sellerCount']).toInt();
          rangeFactor = safeParse(data['bubbleScale']).toDouble();
          if (rangeFactor == 0) rangeFactor = 5.0;

          isBigSignal = data['isBigSignal'] as bool? ?? false;
          isInstitutional = data['isInstitutional'] as bool? ?? false;
          isTrap = data['isTrap'] as bool? ?? false;
          isLiquidation = data['isLiquidation'] as bool? ?? false;
          
          adminOpacity = safeParse(data['bubbleOpacity']).toDouble();
          if (adminOpacity == 0) adminOpacity = 0.65;

          adminGlow = safeParse(data['bubbleGlow']).toDouble();
          adminShowLabel = data['showLabel'] as bool? ?? true;
          adminTag = data['customTag'] as String? ?? "";
          
          adminPulseSpeed = safeParse(data['pulseSpeed']).toDouble();
          if (adminPulseSpeed == 0) adminPulseSpeed = 1.0;
          
          isHeavy = isBigSignal || isInstitutional || isTrap || isLiquidation;
        }
      } 
      // 2. Simulation Logic (if no admin data) — runs for completed candles
      else {
        final bool isLast = (candles.isNotEmpty && candle.candleKey == candles.last.candleKey);
        final nowIST = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
        final bool isOngoing = isLast && (!candle.isClosed && nowIST.isBefore(candle.timeEnd));
        
        // Ongoing candle without admin data shows no simulated volume data until completed
        if (isOngoing) continue;

        final keyInt = candle.timeStart.millisecondsSinceEpoch;
        final random = Random(keyInt);
        final diff = (candle.close - candle.open).abs();
        const durationMin = 5.0; 
        final velocity = diff / durationMin;

        final isSpiking = velocity > spikeThreshold;
        if (isSpiking) {
          spikeStartTimeMs ??= keyInt;
          if (keyInt - spikeStartTimeMs >= 60 * 60 * 1000) isInstitutional = true;
        } else {
          spikeStartTimeMs = null;
        }

        if (isBankNifty) {
          rangeFactor = (range / 40.0).clamp(0.35, 1.15);
          if (velocity > 50) {
            buyerCount = 20000 + random.nextInt(15000);
            sellerCount = 1000 + random.nextInt(3000);
            isHeavy = true;
          } else if (velocity > 20) {
            buyerCount = 8000 + random.nextInt(12000);
            sellerCount = 2000 + random.nextInt(5000);
            isHeavy = buyerCount > 12000;
          } else {
            // Minimum floor: every candle shows some activity
            buyerCount = 800 + random.nextInt(3000);
            sellerCount = 800 + random.nextInt(3000);
          }
        } else {
          rangeFactor = (range / 15.0).clamp(0.35, 1.15);
          if (velocity > 20) {
            buyerCount = 10000 + random.nextInt(8000);
            sellerCount = 500 + random.nextInt(1500);
            isHeavy = true;
          } else if (velocity > 10) {
            buyerCount = 4000 + random.nextInt(6000);
            sellerCount = 1000 + random.nextInt(3000);
            isHeavy = buyerCount > 7000;
          } else {
            // Minimum floor: every candle shows some activity
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

      isHeavy = isHeavy || (buyerCount >= 8500 || sellerCount >= 8500);
      const bool shouldShowPill = true;

      // When fully zoomed out, hide simulated filler data and only show injected data balls and major signals on candlesticks
      if (isZoomedOut && !hasAdminData && !isHeavy && !isBigSignal && !isInstitutional && !isTrap && !isLiquidation) {
        continue;
      }

      // Imbalance check (3x)
      bool isImbalance = false;
      if (buyerCount >= 1000 && sellerCount >= 1000) {
        if (buyerCount >= (sellerCount * 3) || sellerCount >= (buyerCount * 3)) {
          isImbalance = true;
        }
      }

      // --- RENDER GLOW OVERLAY (Exact Center of Candlestick) ---
      // Always centered on the candlestick (no offset or shifting to neighboring candles)
      if (buyerCount > 0 || sellerCount > 0) {
         final isBuyerDominant = buyerCount > sellerCount;
         final dominantCount = isBuyerDominant ? buyerCount : sellerCount;
         
         // Position volume pill in the middle of every candlestick
         final pillY = (candle.open + candle.close) / 2;
         const verticalAlign = ChartAlignment.center;
         
         if (_yVisibleMin != null && _yVisibleMax != null) {
           if (pillY < _yVisibleMin! - 10.0 || pillY > _yVisibleMax! + 10.0) continue;
         }
         
         if (hasAdminData) {
            // Admin Data: Show compact volume pill / AdminGlowingOrb directly on the target candlestick
            Widget glowBubble = _buildGlowOverlay(
              count: dominantCount,
              isBuyer: isBuyerDominant,
              isHeavy: isHeavy,
              scale: rangeFactor,
              opacity: adminOpacity,
              glow: adminGlow,
              showLabel: adminShowLabel && shouldShowLabel,
              isImbalance: isImbalance,
              isRealData: hasAdminData,
              isLocked: false,
              showSuperuserVisuals: isSuperuser && (isInstitutional || isBigSignal),
              isTrap: isTrap,
              isLiquidation: isLiquidation,
              customTag: adminTag,
            );

            // Add interaction for superusers to revoke data
            if (isSuperuser) {
              glowBubble = GestureDetector(
                onLongPress: () {
                  HapticFeedback.mediumImpact();
                  _showRevokeConfirmation(candle.candleKey, adminTag.isNotEmpty ? adminTag : "Footprint Data");
                },
                child: glowBubble,
              );
            }

            if (shouldShowPill) {
              if (isHeavy || hasAdminData) {
                foregroundAnnotations.add(CartesianChartAnnotation(
                   widget: ReplayEntryAnimation(
                     key: ValueKey('glow_${candle.candleKey}'),
                     child: glowBubble,
                   ),
                   coordinateUnit: CoordinateUnit.point,
                   x: candle.candleKey,
                   y: pillY,
                   verticalAlignment: verticalAlign,
                   horizontalAlignment: ChartAlignment.center,
                ));
              } else {
                backgroundAnnotations.add(CartesianChartAnnotation(
                   widget: ReplayEntryAnimation(
                     key: ValueKey('glow_${candle.candleKey}'),
                     child: glowBubble,
                   ),
                   coordinateUnit: CoordinateUnit.point,
                   x: candle.candleKey,
                   y: pillY,
                   verticalAlignment: verticalAlign,
                   horizontalAlignment: ChartAlignment.center,
                ));
              }
            }
          } else {
            // Simulated Data: Single compact volume pill
            if (shouldShowPill) {
              Widget glowBubble = _buildGlowOverlay(
                count: dominantCount,
                isBuyer: isBuyerDominant,
                isHeavy: isHeavy,
                scale: pillScale,
                opacity: 0.65,
                glow: 0.0,
                showLabel: shouldShowLabel,
                isImbalance: isImbalance,
                isRealData: false,
                isLocked: false,
                showSuperuserVisuals: false,
                isTrap: false,
                isLiquidation: false,
              );

              if (isHeavy) {
                foregroundAnnotations.add(CartesianChartAnnotation(
                  widget: ReplayEntryAnimation(
                    key: ValueKey('glow_${candle.candleKey}'),
                    child: glowBubble,
                  ),
                  coordinateUnit: CoordinateUnit.point,
                  x: candle.candleKey,
                  y: pillY,
                  verticalAlignment: verticalAlign,
                  horizontalAlignment: ChartAlignment.center,
                ));
              } else {
                backgroundAnnotations.add(CartesianChartAnnotation(
                  widget: ReplayEntryAnimation(
                    key: ValueKey('glow_${candle.candleKey}'),
                    child: glowBubble,
                  ),
                  coordinateUnit: CoordinateUnit.point,
                  x: candle.candleKey,
                  y: pillY,
                  verticalAlignment: verticalAlign,
                  horizontalAlignment: ChartAlignment.center,
                ));
              }
            }
          }
          
          // --- SIGNAL TAGS (Above Candle) ---
          // Suppress separate signal tags when hasAdminData is true since the AdminGlowingOrb already draws it
          if (adminShowLabel && shouldShowLabel && !hasAdminData) {
            Widget? tagWidget;
            String tagName = "";

            if (isTrap) {
              final prefix = isBuyerDominant ? 'BUY' : 'SELL';
              tagWidget = _buildSignalTag('$prefix TRAP', Colors.orangeAccent);
              tagName = "$prefix TRAP";
            } else if (isLiquidation) {
              final prefix = isBuyerDominant ? 'BUY' : 'SELL';
              tagWidget = _buildSignalTag('$prefix LIQ', Colors.purpleAccent);
              tagName = "$prefix LIQ";
            } else if (isBigSignal) {
              final prefix = isBuyerDominant ? 'BUY' : 'SELL';
              tagWidget = _buildSignalTag(prefix, isBuyerDominant ? Colors.yellowAccent : Colors.redAccent);
              tagName = prefix;
            } else if (adminTag.isNotEmpty) {
              tagWidget = _buildSignalTag(adminTag, Colors.white);
              tagName = adminTag;
            }

            if (tagWidget != null) {
              // Add interaction for superusers to revoke data
              if (isSuperuser && hasAdminData) {
                tagWidget = GestureDetector(
                  onLongPress: () {
                    HapticFeedback.mediumImpact();
                    _showRevokeConfirmation(candle.candleKey, tagName);
                  },
                  child: tagWidget,
                );
              }

              foregroundAnnotations.add(CartesianChartAnnotation(
                widget: ReplayEntryAnimation(
                  key: ValueKey('tag_${candle.candleKey}'),
                  child: tagWidget,
                ),
                coordinateUnit: CoordinateUnit.point,
                x: candle.candleKey,
                y: candle.high,
                verticalAlignment: ChartAlignment.near,
                horizontalAlignment: ChartAlignment.center,
              ));
            }
          }
       }

      // --- NEW FEATURE: IMBALANCE STACKING VISUALS ---
      if (candle.imbalances.isNotEmpty) {
        for (final imb in candle.imbalances) {
          final isBuyImb = imb.type == 'buy';
          backgroundAnnotations.add(CartesianChartAnnotation(
            widget: Container(
              height: 1.5,
              width: 50 * _scaleFactor, // Visual length
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    (isBuyImb ? const Color(0xFF00FF41) : const Color(0xFFFF003C)).withValues(alpha: 0.8),
                    Colors.transparent,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isBuyImb ? const Color(0xFF00FF41) : const Color(0xFFFF003C)).withValues(alpha: 0.3),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
            coordinateUnit: CoordinateUnit.point,
            x: candle.candleKey,
            y: imb.price,
            horizontalAlignment: ChartAlignment.near,
          ));
        }
      }

      // --- NEW FEATURE: DELTA DIVERGENCE ---
      // Compare with previous candle
      final index = candles.indexOf(candle);
      if (index > 0) {
        final prev = candles[index - 1];
        final currentDelta = candle.delta;
        final prevDelta = prev.delta;
        
        // Bearish Divergence: Higher High vs Lower Delta
        if (candle.high > prev.high && currentDelta < prevDelta && candle.isBearish) {
           foregroundAnnotations.add(CartesianChartAnnotation(
            widget: AnimatedBuilder(
              animation: _flashAnimation,
              builder: (context, child) {
                return Opacity(
                  opacity: 0.5 + (0.5 * _flashAnimation.value),
                  child: Transform.scale(
                    scale: 1.0 + (0.2 * _flashAnimation.value),
                    child: Text(
                      currentDelta.toInt().abs().toString(),
                      style: const TextStyle(
                        color: Color(0xFFFF003C), // Red
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        shadows: [Shadow(color: Colors.black, blurRadius: 2)],
                      ),
                    ),
                  ),
                );
              },
            ),
            coordinateUnit: CoordinateUnit.point,
            x: candle.candleKey,
            y: candle.high,
            verticalAlignment: ChartAlignment.near,
            horizontalAlignment: ChartAlignment.center,
          ));
        }
        // Bullish Divergence: Lower Low vs Higher Delta
        else if (candle.low < prev.low && currentDelta > prevDelta && candle.isBullish) {
           foregroundAnnotations.add(CartesianChartAnnotation(
            widget: AnimatedBuilder(
              animation: _flashAnimation,
              builder: (context, child) {
                return Opacity(
                  opacity: 0.5 + (0.5 * _flashAnimation.value), // Blinking effect
                  child: Transform.scale(
                    scale: 1.0 + (0.2 * _flashAnimation.value),
                    child: Text(
                      currentDelta.toInt().abs().toString(),
                      style: const TextStyle(
                        color: Color(0xFF00FF41), // Green
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        shadows: [Shadow(color: Colors.black, blurRadius: 2)],
                      ),
                    ),
                  ),
                );
              },
            ),
            coordinateUnit: CoordinateUnit.point,
            x: candle.candleKey,
            y: candle.low,
            verticalAlignment: ChartAlignment.far,
            horizontalAlignment: ChartAlignment.center,
          ));
        }

      }
    }
    
    // Add Footprints (High Zoom only)
    for (final candle in candles) {
      if (!candleIndexMap.containsKey(candle.candleKey)) continue;
      final String? activeKey = _findActiveOrderflowKey(candle);
      if (activeKey != null) {
        final rawFootprint = orderflowData[activeKey]!['footprint'] as Map<String, dynamic>?;
        if (rawFootprint != null && rawFootprint.isNotEmpty) {
          // visibleRangeFactor check from earlier loop
          final visibleRangeFactor = (_yVisibleMax != null && _yVisibleMin != null) 
              ? (_yVisibleMax! - _yVisibleMin!) 
              : 0.0;
              
          if (visibleRangeFactor > 0 && visibleRangeFactor < 200) {
             final footprint = rawFootprint.map((k, v) => MapEntry(
              double.parse(k),
              PriceLevelData(
                buyVolume: _parseNum(v['buyVolume']).toInt(),
                sellVolume: _parseNum(v['sellVolume']).toInt(),
              ),
            ));

            backgroundAnnotations.add(CartesianChartAnnotation(
              widget: _buildFootprintOverlay(candle, footprint),
              coordinateUnit: CoordinateUnit.point,
              x: candle.candleKey,
              y: candle.high,
              verticalAlignment: ChartAlignment.near,
              horizontalAlignment: ChartAlignment.center,
            ));
          }
        }
      }
    }



    return backgroundAnnotations + foregroundAnnotations;
  }

  num _parseNum(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value;
    if (value is String) {
      if (value.isEmpty) return 0;
      return num.tryParse(value) ?? 0;
    }
    return 0;
  }

  void _setupGhostOrdersListener() {
    _ghostOrdersSubscription?.cancel();
    final userEmail = ref.read(authProvider).user?.email;
    _ghostOrdersSubscription = ref.read(orderflowServiceProvider).getGhostOrdersStream('NIFTY50', currentUserEmail: userEmail).listen((ghosts) {
      if (mounted) {
        setState(() {
          _activeGhostOrders = ghosts;
          final activeIds = ghosts.map((g) => g.id).toSet();
          _triggeredGhostIds.removeWhere((id) => !activeIds.contains(id));
          // Set initial baseline price on broadcast load to prevent immediate false triggers
          if (_animatedCloseNotifier.value > 0) {
            _lastCheckedGhostPrice = _animatedCloseNotifier.value;
          }
        });
      }
    });
  }

  void _checkGhostOrderTriggers(double currentPrice) {
    final symbol = ref.read(selectedInstrumentProvider);
    if (symbol != 'NIFTY50') return;
    
    // Only administrators (admin or superuser) can run level triggers/injections
    final authState = ref.read(authProvider);
    final user = authState.user;
    final isSuperuser = OrderflowService.isSuperuser(user?.email);
    final isAdmin = user?.isAdmin ?? false;
    if (!isSuperuser && !isAdmin) return;
    
    if (_activeGhostOrders.isEmpty) return;
    
    final lastPrice = _lastCheckedGhostPrice;
    _lastCheckedGhostPrice = currentPrice;
    
    // Baseline check: require a valid previous price to detect actual live price crossover
    if (lastPrice == null || lastPrice <= 0) return;
    
    for (final ghost in _activeGhostOrders) {
      if (_triggeredGhostIds.contains(ghost.id)) continue;
      
      // Require actual live price crossover (crossing up or crossing down through the level)
      final isCrossingUp = lastPrice < ghost.triggerPrice && currentPrice >= ghost.triggerPrice;
      final isCrossingDown = lastPrice > ghost.triggerPrice && currentPrice <= ghost.triggerPrice;
      
      if (isCrossingUp || isCrossingDown) {
        _triggerGhostOrder(ghost);
      }
    }
  }

  Future<void> _triggerGhostOrder(GhostOrder ghost) async {
    _triggeredGhostIds.add(ghost.id);
    AudioService.playTradeSound(isInstitutional: ghost.isInstitutional || ghost.isBigSignal);
    HapticFeedback.vibrate();
    
    final now = DateTime.now();
    final minute = (now.minute ~/ 5) * 5;
    final candleTime = DateTime(now.year, now.month, now.day, now.hour, minute);
    
    await ref.read(orderflowServiceProvider).realizeGhostOrder(ghost, candleTime);
  }

  Future<void> _startSimilarPatternScan([DateTime? targetTimeOverride]) async {
    final symbol = ref.read(selectedInstrumentProvider);
    if (symbol != 'NIFTY50') return;

    final DateTime targetTime = targetTimeOverride ?? _selectedCandleTime ?? DateTime.now();
    final List<String> scanStocks = NiftyStocks.stocks.keys.toList();

    setState(() {
      _isScanningSimilarPatterns = true;
      _scanProgress = 0;
      _scanTotal = scanStocks.length;
      _suggestedSimilarStocks = [];
      _selectedSimilarStocksToInject.clear();
    });

    try {
      final repo = ref.read(candleRepositoryProvider);
      final cacheSource = ref.read(localCacheDataSourceProvider);
      
      final niftyCandles = ref.read(candleStreamProvider).candles;
      if (niftyCandles.isEmpty) {
        if (mounted) setState(() => _isScanningSimilarPatterns = false);
        return;
      }

      final targetDateStart = DateTime(targetTime.year, targetTime.month, targetTime.day);
      final targetDateEnd = targetDateStart.add(const Duration(days: 1));
      final niftyToday = niftyCandles.where((c) =>
          c.timeStart.isAfter(targetDateStart) &&
          c.timeStart.isBefore(targetDateEnd) &&
          (c.timeStart.isBefore(targetTime) || c.timeStart.isAtSameMomentAs(targetTime))
      ).toList()..sort((a, b) => a.timeStart.compareTo(b.timeStart));

      if (niftyToday.isEmpty) {
        if (mounted) setState(() => _isScanningSimilarPatterns = false);
        return;
      }

      final firstHourEnd = targetDateStart.add(const Duration(hours: 10, minutes: 15));
      final niftyFirstHour = niftyToday.where((c) =>
          c.timeEnd.isBefore(firstHourEnd) || c.timeEnd.isAtSameMomentAs(firstHourEnd)
      ).toList();
      
      double? niftyFirstHourHigh;
      double? niftyFirstHourLow;
      if (niftyFirstHour.isNotEmpty) {
        niftyFirstHourHigh = niftyFirstHour.map((c) => c.high).reduce(math.max);
        niftyFirstHourLow = niftyFirstHour.map((c) => c.low).reduce(math.min);
      }

      final niftySessionHigh = niftyToday.map((c) => c.high).reduce(math.max);
      final niftySessionLow = niftyToday.map((c) => c.low).reduce(math.min);
      final bool niftyBrokeHigh = niftyFirstHourHigh != null && niftySessionHigh > niftyFirstHourHigh;
      final bool niftyBrokeLow = niftyFirstHourLow != null && niftySessionLow < niftyFirstHourLow;
      final double niftyOpen = niftyToday.first.open;

      final List<Map<String, dynamic>> suggestions = [];

      for (int i = 0; i < scanStocks.length; i++) {
        final stock = scanStocks[i];
        if (!mounted) break;

        if (mounted) {
          setState(() => _scanProgress = i + 1);
        }

        try {
          List<CandleModel> stockCandles = await cacheSource.getCachedCandles(stock);

          final bool isUpToDate = stockCandles.any((c) =>
              c.timeStart.year == targetTime.year &&
              c.timeStart.month == targetTime.month &&
              c.timeStart.day == targetTime.day
          );

          if (!isUpToDate) {
            stockCandles = await repo.fetchHistoricalCandles(stock)
                .timeout(const Duration(seconds: 5), onTimeout: () => stockCandles);
          }

          if (stockCandles.isEmpty) continue;

          final stockToday = stockCandles.where((c) =>
              c.timeStart.isAfter(targetDateStart) &&
              c.timeStart.isBefore(targetDateEnd) &&
              (c.timeStart.isBefore(targetTime) || c.timeStart.isAtSameMomentAs(targetTime))
          ).toList()..sort((a, b) => a.timeStart.compareTo(b.timeStart));

          if (stockToday.isEmpty) continue;

          final Map<int, CandleModel> stockMap = {
            for (var c in stockToday) c.timeStart.millisecondsSinceEpoch: c
          };

          final List<double> niftyPrices = [];
          final List<double> stockPrices = [];
          final double stockOpen = stockToday.first.open;

          for (final nc in niftyToday) {
            final sc = stockMap[nc.timeStart.millisecondsSinceEpoch];
            if (sc != null && niftyOpen != 0 && stockOpen != 0) {
              niftyPrices.add((nc.close - niftyOpen) / niftyOpen);
              stockPrices.add((sc.close - stockOpen) / stockOpen);
            }
          }

          if (niftyPrices.length < 3) continue;

          final double correlation = _calculateCorrelation(niftyPrices, stockPrices);

          final stockFirstHour = stockToday.where((c) =>
              c.timeEnd.isBefore(firstHourEnd) || c.timeEnd.isAtSameMomentAs(firstHourEnd)
          ).toList();
          double? stockFHH, stockFHL;
          if (stockFirstHour.isNotEmpty) {
            stockFHH = stockFirstHour.map((c) => c.high).reduce(math.max);
            stockFHL = stockFirstHour.map((c) => c.low).reduce(math.min);
          }
          final double stockSessionHigh = stockToday.map((c) => c.high).reduce(math.max);
          final double stockSessionLow = stockToday.map((c) => c.low).reduce(math.min);
          final bool stockBrokeHigh = stockFHH != null && stockSessionHigh > stockFHH;
          final bool stockBrokeLow = stockFHL != null && stockSessionLow < stockFHL;

          double sumDiff = 0.0;
          for (int k = 0; k < niftyPrices.length; k++) {
            sumDiff += (niftyPrices[k] - stockPrices[k]).abs();
          }
          final double avgDiff = sumDiff / niftyPrices.length;
          final double percentageSimilarity = (1.0 - (avgDiff / 0.02)).clamp(0.0, 1.0) * 100.0;

          double score = (correlation > 0 ? correlation * 50.0 : 0.0) + (percentageSimilarity * 0.30);
          if (niftyBrokeHigh == stockBrokeHigh) score += 10;
          if (niftyBrokeLow == stockBrokeLow) score += 10;
          final int finalScore = score.round().clamp(0, 99);

          if (finalScore >= 50) {
            suggestions.add({
              'symbol': stock,
              'score': finalScore,
              'brokeHigh': stockBrokeHigh,
              'brokeLow': stockBrokeLow,
            });
          }
        } catch (e) {
          debugPrint('$stock error in chart scan: $e');
        }
      }

      suggestions.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

      if (mounted) {
        setState(() {
          _suggestedSimilarStocks = suggestions;
          _selectedSimilarStocksToInject.clear();
          for (final s in suggestions) {
            if ((s['score'] as int) >= 80) {
              _selectedSimilarStocksToInject.add(s['symbol'] as String);
            }
          }
          _isScanningSimilarPatterns = false;
          _scanProgress = 0;
        });
      }
    } catch (e, stack) {
      debugPrint('Chart scan general error: $e\n$stack');
      if (mounted) {
        setState(() {
          _isScanningSimilarPatterns = false;
          _scanProgress = 0;
        });
      }
    }
  }

  double _calculateCorrelation(List<double> x, List<double> y) {
    final int n = x.length;
    double sumX = 0, sumY = 0, sumXY = 0;
    double sumX2 = 0, sumY2 = 0;

    for (int i = 0; i < n; i++) {
      sumX += x[i];
      sumY += y[i];
      sumXY += x[i] * y[i];
      sumX2 += x[i] * x[i];
      sumY2 += y[i] * y[i];
    }

    final double num = (n * sumXY) - (sumX * sumY);
    final double den = math.sqrt(((n * sumX2) - (sumX * sumX)) * ((n * sumY2) - (sumY * sumY)));

    if (den == 0) return 0.0;
    return num / den;
  }

  Widget _buildFootprintOverlay(Candle candle, Map<double, PriceLevelData> footprint) {
    // Sort prices high to low for vertical display
    final sortedPrices = footprint.keys.toList()..sort((a, b) => b.compareTo(a));
    
    // Limits to prevent overflow if too many levels
    final displayPrices = sortedPrices.take(20).toList();

    return Container(
      width: 50 * _scaleFactor,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: Colors.white24, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: displayPrices.map((p) {
          final data = footprint[p]!;
          return _buildFootprintRow(data, isInjected: candle.isInjected);
        }).toList(),
      ),
    );
  }

  Widget _buildFootprintRow(PriceLevelData data, {bool isInjected = false}) {
    const double maxRef = 5000.0;
    final bAlpha = (data.buyVolume / maxRef).clamp(0.1, 0.9);
    final sAlpha = (data.sellVolume / maxRef).clamp(0.1, 0.9);

    return Container(
      height: 10, // Small compact rows
      margin: const EdgeInsets.symmetric(vertical: 0.5),
      child: Row(
        children: [
          Expanded(
            child: Container(
              alignment: Alignment.centerRight,
              decoration: BoxDecoration(color: AppTheme.bullColor.withValues(alpha: bAlpha)),
              padding: const EdgeInsets.only(right: 2),
              child: Text(
                isInjected ? data.buyVolume.toString() : '${(data.buyVolume/1000).toStringAsFixed(1)}K',
                style: const TextStyle(color: Colors.white, fontSize: 5, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const VerticalDivider(width: 0.5, color: Colors.white24),
          Expanded(
            child: Container(
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(color: AppTheme.bearColor.withValues(alpha: sAlpha)),
              padding: const EdgeInsets.only(left: 2),
              child: Text(
                isInjected ? data.sellVolume.toString() : '${(data.sellVolume/1000).toStringAsFixed(1)}K',
                style: const TextStyle(color: Colors.white, fontSize: 5, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlowOverlay({
    required int count,
    required bool isBuyer,
    required bool isHeavy,
    required double scale,
    required bool isRealData,
    double opacity = 0.65,
    double glow = 0.0,
    bool showLabel = true,
    bool isImbalance = false,
    bool isLocked = false,
    bool showSuperuserVisuals = false,
    bool isTrap = false,
    bool isLiquidation = false,
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

    // Base color: green for buyers, red for sellers
    Color baseColor = isBuyer ? const Color(0xFF00E676) : const Color(0xFFFF5252);
    
    if (isTrap) {
      baseColor = Colors.orangeAccent;
    } else if (isLiquidation) {
      baseColor = Colors.purpleAccent;
    }

    final double adjustedFontSize = (isRealData ? 11.0 : 10.0) * scale;
    final double horizontalPadding = (isRealData ? 8.0 : 6.0) * scale;
    final double verticalPadding = (isRealData ? 4.0 : 3.0) * scale;
    final double borderRadius = 4.0 * scale;

    // Clean compact volume pill — matches reference design (renders as a round ball/circle for admin injected data)
    final pillWidget = Container(
      width: isRealData ? 24 * scale : null,
      height: isRealData ? 24 * scale : null,
      alignment: isRealData ? Alignment.center : null,
      padding: isRealData
          ? EdgeInsets.zero
          : EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
      decoration: BoxDecoration(
        shape: isRealData ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isRealData ? null : BorderRadius.circular(borderRadius),
        color: isRealData
            ? baseColor.withValues(alpha: 0.9)
            : baseColor.withValues(alpha: 0.75),
        border: Border.all(
          color: isRealData
              ? Colors.white.withValues(alpha: 0.8)
              : baseColor.withValues(alpha: 0.3),
          width: (isRealData ? 1.5 : 0.8) * scale,
        ),
        boxShadow: [
          if (isRealData || isHeavy)
            BoxShadow(
              color: baseColor.withValues(alpha: 0.5),
              blurRadius: isRealData ? 10 * scale : 6 * scale,
              spreadRadius: isRealData ? 2 * scale : 0,
            ),
        ],
      ),
      child: showLabel
          ? (isLocked
              ? Icon(Icons.lock, color: Colors.white, size: 10 * scale)
              : Text(
                  _formatNumber(count, fullNumber: isRealData),
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isRealData ? (adjustedFontSize - 2.0) : adjustedFontSize,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3 * scale,
                    height: 1.0,
                  ),
                ))
          : SizedBox(
              width: 8 * scale,
              height: 8 * scale,
            ),
    );

    // For heavy admin data: add a subtle pulsing border, WHALE tag
    if (isHeavy && isRealData) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSuperuserVisuals && showLabel)
            Container(
              margin: EdgeInsets.only(bottom: 2 * scale),
              padding: EdgeInsets.symmetric(horizontal: 4 * scale, vertical: 1 * scale),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(3 * scale),
                border: Border.all(color: Colors.amber, width: 0.8 * scale),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star, color: Colors.amber, size: 7 * scale),
                  SizedBox(width: 2 * scale),
                  Text(
                    'WHALE',
                    style: TextStyle(
                      color: Colors.amber,
                      fontSize: 7 * scale,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8 * scale,
                    ),
                  ),
                ],
              ),
            ),
          pillWidget,
        ],
      );
    }

    return pillWidget;
  }

  String _formatNumber(int count, {bool fullNumber = false}) {
    if (fullNumber) return count.toString();
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 100000) return '${(count / 1000).round()}K';
    if (count >= 10000) return '${(count / 1000).toStringAsFixed(0)}K';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }



  Widget _buildSignalTag(String tag, Color color) {
    Color bgColor = Colors.black;
    Color textColor = color;
    double borderWidth = 1.0;
    
    if (tag.contains('WHALE') || tag.contains('BIG') || tag.contains('BUY')) {
      bgColor = const Color(0xFFFFD700).withValues(alpha: 0.2);
      textColor = const Color(0xFFFFD700);
      borderWidth = 1.5;
    } else if (tag.contains('TRAP')) {
       bgColor = Colors.orangeAccent.withValues(alpha: 0.2);
       textColor = Colors.orangeAccent;
       borderWidth = 1.5;
    } else if (tag.contains('LIQUIDATION') || tag.contains('LIQ')) {
       bgColor = Colors.purpleAccent.withValues(alpha: 0.2);
       textColor = Colors.purpleAccent;
       borderWidth = 1.5;
    } else if (tag.contains('SELL')) {
       bgColor = Colors.redAccent.withValues(alpha: 0.2);
       textColor = Colors.redAccent;
       borderWidth = 1.5;
    } else if (tag.contains('INSTITUTIONAL')) {
       bgColor = Colors.white.withValues(alpha: 0.1);
       textColor = Colors.white;
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: textColor.withValues(alpha: 0.5), width: borderWidth),
        boxShadow: [
          BoxShadow(color: textColor.withValues(alpha: 0.1), blurRadius: 6, spreadRadius: 0),
        ],
      ),
      child: Text(
        tag,
        style: TextStyle(
          color: textColor,
          fontSize: 9.0 * _scaleFactor,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
    );
  }



  Widget _buildOrderflowInputPanel(String instrument) {
    if (_selectedCandleTime == null) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20, offset: const Offset(0, -5)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryCyan.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      instrument,
                      style: const TextStyle(color: AppTheme.primaryCyan, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    intl.DateFormat('dd MMM | hh:mm a').format(_selectedCandleTime!),
                    style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white30, size: 20),
                onPressed: () => setState(() => _showOrderflowInput = false),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          
          // Main Volume Inputs
          Row(
            children: [
              Expanded(child: _buildPanelTextField(_buyerController, 'BUYERS', AppTheme.bullColor)),
              const SizedBox(width: 12),
              Expanded(child: _buildPanelTextField(_sellerController, 'SELLERS', AppTheme.bearColor)),
            ],
          ),
          const SizedBox(height: 8),
          
          // Bubble Scaling
          _buildScaleSelector(),
          const SizedBox(height: 16),
          
          _buildFrequencySelector(),
          const SizedBox(height: 16),
          
          _buildOpacitySelector(),
          const SizedBox(height: 12),
          _buildPresetsSection(),
          const SizedBox(height: 16),
          
          // Tactical Toggles
          Row(
            children: [
              Expanded(child: _buildBigSignalToggle()),
              const SizedBox(width: 10),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildInstitutionalToggle()),
              const SizedBox(width: 10),
              Expanded(child: _buildGhostModeToggle()),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildTrapToggle()),
              const SizedBox(width: 10),
              Expanded(child: _buildLiquidationToggle()),
            ],
          ),
          const SizedBox(height: 10),
          if (AppConstants.isMasterAdmin(ref.read(authProvider).user?.email)) ...[
            Row(
              children: [
                Expanded(child: _buildAdminOnlyToggle()),
                const SizedBox(width: 10),
                const Expanded(child: SizedBox.shrink()),
              ],
            ),
            const SizedBox(height: 10),
          ],
          
          // Ghost Mode Extra Field
          if (_isGhostMode) ...[
            const SizedBox(height: 16),
            _buildPanelTextField(_ghostTriggerController, 'TRIGGER PRICE (GHOST MODE)', AppTheme.goldColor),
            if (instrument == 'NIFTY50') ...[
              const SizedBox(height: 12),
              _buildCorrelatedStocksSection(),
            ],
          ],
          
          const SizedBox(height: 24),
          
          // Action Buttons
          _buildSaveButton(),
        ],
      ),
    );
  }

  Widget _buildPresetsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PRESET TEMPLATES',
          style: TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        const SizedBox(height: 6),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 2.3,
          children: [
            _buildPresetChip('BUY TRAP', Colors.orangeAccent, () {
              _applyTemplate(buy: 45000, sell: 0, scale: 15.0, pulse: 1.5, opacity: 0.8, isTrap: true);
            }),
            _buildPresetChip('SELL TRAP', Colors.orangeAccent, () {
              _applyTemplate(buy: 0, sell: 45000, scale: 15.0, pulse: 1.5, opacity: 0.8, isTrap: true);
            }),
            _buildPresetChip('BUY LIQ', Colors.purpleAccent, () {
              _applyTemplate(buy: 75000, sell: 0, scale: 20.0, pulse: 1.8, opacity: 0.85, isLiq: true);
            }),
            _buildPresetChip('SELL LIQ', Colors.purpleAccent, () {
              _applyTemplate(buy: 0, sell: 75000, scale: 20.0, pulse: 1.8, opacity: 0.85, isLiq: true);
            }),
            _buildPresetChip('BUY BIG', AppTheme.bullColor, () {
              _applyTemplate(buy: 150000, sell: 0, scale: 25.0, pulse: 1.2, opacity: 0.9, isBig: true);
            }),
            _buildPresetChip('SELL BIG', AppTheme.bearColor, () {
              _applyTemplate(buy: 0, sell: 125000, scale: 25.0, pulse: 1.2, opacity: 0.9, isBig: true);
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildPresetChip(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 8,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  void _applyTemplate({
    required int buy,
    required int sell,
    required double scale,
    required double pulse,
    required double opacity,
    bool isTrap = false,
    bool isLiq = false,
    bool isBig = false,
  }) {
    final rand = math.Random();
    int randBuy = buy > 0 ? (buy * (1 + ((rand.nextDouble() * 10) - 5) / 100)).round() : 0;
    int randSell = sell > 0 ? (sell * (1 + ((rand.nextDouble() * 10) - 5) / 100)).round() : 0;
    setState(() {
      _buyerController.text = randBuy > 0 ? randBuy.toString() : '';
      _sellerController.text = randSell > 0 ? randSell.toString() : '';
      _selectedBubbleScale = scale;
      _selectedPulseSpeed = pulse;
      _selectedBubbleOpacity = opacity;
      _isBigSignalSelected = isBig;
      _isTrapSelected = isTrap;
      _isLiquidationSelected = isLiq;
    });
  }

  void _showRevokeConfirmation(String candleKey, String label) {
    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: AlertDialog(
          backgroundColor: Colors.black87,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppTheme.bearColor.withValues(alpha: 0.3), width: 1.5),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppTheme.bearColor, size: 24),
              SizedBox(width: 12),
              Text('REVOKE DATA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1)),
            ],
          ),
          content: Text(
            'Are you sure you want to revoke the "$label" data from this candle?\n\nThis action cannot be undone.',
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL', style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _revokeAdminInjectedData(candleKey);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.bearColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('REVOKE', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _revokeAdminInjectedData(String candleKey) async {
    final user = ref.read(authProvider).user;
    if (!OrderflowService.isSuperuser(user?.email)) return;

    try {
      final symbol = ref.read(selectedInstrumentProvider);
      final orderflowRepo = ref.read(orderflowRepositoryProvider);

      await orderflowRepo.deleteOrderflowDirect(
        candleKey: candleKey,
        symbol: symbol,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('INJECTED DATA REVOKED'),
            backgroundColor: AppTheme.bearColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
        HapticFeedback.heavyImpact();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ERROR REVOKING DATA: $e'),
            backgroundColor: AppTheme.bearColor,
          ),
        );
      }
    }
  }


  Widget _buildPanelTextField(TextEditingController controller, String label, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white10)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: color.withValues(alpha: 0.5))),
          ),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return Row(
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              _buyerController.clear();
              _sellerController.clear();
              _ghostTriggerController.clear();
              _priceLevelController.clear();
              _levelBuyerController.clear();
              _levelSellerController.clear();
               _isInstitutionalSelected = false;
              _isBigSignalSelected = false;
              _isAdminOnlySelected = false;

              _isTrapSelected = false;
              _isLiquidationSelected = false;
              _selectedBubbleScale = 5.0;
              _selectedPulseSpeed = 1.0;
              _selectedBubbleOpacity = 0.65;
              _autoFadeMinutes = 0;
            });
            HapticFeedback.lightImpact();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 18),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: _saveOrderflow,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.primaryCyan,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(color: AppTheme.primaryCyan.withValues(alpha: 0.3), blurRadius: 10, spreadRadius: -2),
                ],
              ),
              child: const Center(
                child: Text(
                  'INJECT DATA',
                  style: TextStyle(color: AppTheme.bgColor, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1),
                ),
              ),
            ),
          ),
        ),

        if (orderflowData.containsKey(_selectedCandleTime?.millisecondsSinceEpoch.toString())) ...[
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _revokeOrderflow,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.bearColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.bearColor.withValues(alpha: 0.5), width: 1.5),
              ),
              child: const Row(
                children: [
                  Icon(Icons.delete_sweep_rounded, color: AppTheme.bearColor, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'REVOKE',
                    style: TextStyle(color: AppTheme.bearColor, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _revokeOrderflow() async {
    if (_selectedCandleTime == null) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('REVOKE SIGNAL', style: TextStyle(color: AppTheme.bearColor, fontWeight: FontWeight.w900, fontSize: 16)),
        content: const Text('This will permanently delete the orderflow signal for this candle from both Firestore and Local Cache.', style: TextStyle(color: Colors.white, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('DELETE', style: TextStyle(color: AppTheme.bearColor, fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (confirm != true) return;

    final symbol = ref.read(selectedInstrumentProvider);
    final orderflowService = ref.read(orderflowServiceProvider);
    
    try {
      await orderflowService.revokeOrderflow(
        symbol: symbol,
        candleTime: _selectedCandleTime!,
      );
      
      if (mounted) {
        _buyerController.clear();
        _sellerController.clear();
        _isInstitutionalSelected = false;
        _isBigSignalSelected = false;
        _isAdminOnlySelected = false;

        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signal revoked successfully'), backgroundColor: AppTheme.primaryCyan),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error revoking signal: $e'), backgroundColor: AppTheme.bearColor),
        );
      }
    }
  }

  Widget _buildScaleSelector() {
    final scales = [1.0, 5.0, 10.0, 20.0, 30.0, 50.0];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'BUBBLE SIZE (POINTS)',
          style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: scales.map((s) => GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _selectedBubbleScale = s);
              },
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _selectedBubbleScale == s ? AppTheme.primaryCyan.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _selectedBubbleScale == s ? AppTheme.primaryCyan : Colors.white12),
                ),
                child: Text(
                  '${s.toInt()} PT',
                  style: TextStyle(
                    color: _selectedBubbleScale == s ? AppTheme.primaryCyan : Colors.white70,
                    fontSize: 9, 
                    fontWeight: FontWeight.w900
                  ),
                ),
              ),
            )).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildFrequencySelector() {
    final frequencies = [0.5, 1.0, 2.0, 3.0, 5.0];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PULSE FREQUENCY (SPEED)',
          style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: frequencies.map((s) => GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _selectedPulseSpeed = s);
              },
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _selectedPulseSpeed == s ? AppTheme.primaryCyan.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _selectedPulseSpeed == s ? AppTheme.primaryCyan : Colors.white12),
                ),
                child: Text(
                  '${s}X',
                  style: TextStyle(
                    color: _selectedPulseSpeed == s ? AppTheme.primaryCyan : Colors.white70,
                    fontSize: 9, 
                    fontWeight: FontWeight.w900
                  ),
                ),
              ),
            )).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildOpacitySelector() {
    final opacities = [0.2, 0.4, 0.65, 0.85, 1.0];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'BUBBLE OPACITY',
          style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: opacities.map((s) => GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _selectedBubbleOpacity = s);
              },
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _selectedBubbleOpacity == s ? AppTheme.primaryCyan.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _selectedBubbleOpacity == s ? AppTheme.primaryCyan : Colors.white12),
                ),
                child: Text(
                  '${(s * 100).toInt()}%',
                  style: TextStyle(
                    color: _selectedBubbleOpacity == s ? AppTheme.primaryCyan : Colors.white70,
                    fontSize: 9, 
                    fontWeight: FontWeight.w900
                  ),
                ),
              ),
            )).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildGhostModeToggle() {
    return _buildTacticalToggle(
      icon: Icons.visibility_off_rounded,
      label: 'GHOST MODE',
      value: _isGhostMode,
      onChanged: (v) {
        setState(() => _isGhostMode = v);
        if (v && ref.read(selectedInstrumentProvider) == 'NIFTY50' && _suggestedSimilarStocks.isEmpty && !_isScanningSimilarPatterns) {
          _startSimilarPatternScan();
        }
      },
      activeColor: AppTheme.goldColor,
    );
  }

  Widget _buildCorrelatedStocksSection() {
    if (_isScanningSimilarPatterns) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryCyan),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'SCANNING CORRELATED STOCKS ($_scanProgress/$_scanTotal)...',
                  style: const TextStyle(color: AppTheme.primaryCyan, fontSize: 8, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: _scanTotal > 0 ? _scanProgress / _scanTotal : null,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryCyan),
                minHeight: 2,
              ),
            ),
          ],
        ),
      );
    }

    if (_suggestedSimilarStocks.isEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'CORRELATED STOCKS',
            style: TextStyle(color: Colors.white30, fontSize: 8, fontWeight: FontWeight.bold),
          ),
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              _startSimilarPatternScan();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryCyan.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppTheme.primaryCyan.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'SCAN NOW',
                style: TextStyle(color: AppTheme.primaryCyan, fontSize: 8, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'CORRELATED STOCKS (${_selectedSimilarStocksToInject.length} SELECTED)',
              style: const TextStyle(color: AppTheme.primaryCyan, fontSize: 8, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      if (_selectedSimilarStocksToInject.length == _suggestedSimilarStocks.length) {
                        _selectedSimilarStocksToInject.clear();
                      } else {
                        for (final s in _suggestedSimilarStocks) {
                          _selectedSimilarStocksToInject.add(s['symbol'] as String);
                        }
                      }
                    });
                  },
                  child: Text(
                    _selectedSimilarStocksToInject.length == _suggestedSimilarStocks.length ? 'DESELECT ALL' : 'SELECT ALL',
                    style: const TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    _startSimilarPatternScan();
                  },
                  child: const Text(
                    'RESCAN',
                    style: TextStyle(color: AppTheme.primaryCyan, fontSize: 8, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 28,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _suggestedSimilarStocks.length,
            itemBuilder: (context, index) {
              final s = _suggestedSimilarStocks[index];
              final String sym = s['symbol'];
              final int score = s['score'];
              final isChecked = _selectedSimilarStocksToInject.contains(sym);
              final isStrong = score >= 80;
              final Color color = isStrong ? AppTheme.bullColor : Colors.amber;

              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      if (isChecked) {
                        _selectedSimilarStocksToInject.remove(sym);
                      } else {
                        _selectedSimilarStocksToInject.add(sym);
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isChecked ? color.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isChecked ? color : Colors.white.withValues(alpha: 0.05),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isChecked) ...[
                          Icon(Icons.check_rounded, color: color, size: 10),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          '$sym ($score%)',
                          style: TextStyle(
                            color: isChecked ? Colors.white : Colors.white54,
                            fontSize: 8,
                            fontWeight: isChecked ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _saveOrderflow() async {
    if (_selectedCandleTime == null) return;
    
    final symbol = ref.read(selectedInstrumentProvider);
    final buyerCount = int.tryParse(_buyerController.text) ?? 0;
    final sellerCount = int.tryParse(_sellerController.text) ?? 0;
    
    if (buyerCount == 0 && sellerCount == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('At least one volume required'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    List<String> additionalIndices = [];
    if (symbol == 'NIFTY50') {
      final shouldInjectOthers = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: AppTheme.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'INJECT IN OTHER INDICES?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: const Text(
            'Do you also want to inject this data in FINNIFTY, SENSEX, and BANKNIFTY?',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('NO', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('YES', style: TextStyle(color: AppTheme.primaryCyan, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (shouldInjectOthers == true) {
        additionalIndices.addAll(['FINNIFTY', 'SENSEX', 'BANKNIFTY']);
      }
    }

    // strictly follow manual toggle (Removed volume comparison)
    final bool effectiveBigSignal = _isBigSignalSelected;

    // Footprint parsing
    Map<double, PriceLevelData>? footprint;
    final priceLvl = double.tryParse(_priceLevelController.text);
    final lBuyer = int.tryParse(_levelBuyerController.text) ?? 0;
    final lSeller = int.tryParse(_levelSellerController.text) ?? 0;
    
    if (priceLvl != null && (lBuyer > 0 || lSeller > 0)) {
       footprint = {
          priceLvl: PriceLevelData(buyVolume: lBuyer, sellVolume: lSeller),
       };
    }

    if (_isGhostMode) {
      final triggerPrice = double.tryParse(_ghostTriggerController.text);
      if (triggerPrice == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Trigger price required for Ghost Mode'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      final ghost = GhostOrder(
        id: 'GHOST_${DateTime.now().millisecondsSinceEpoch}',
        symbol: symbol,
        triggerSymbol: symbol,
        triggerPrice: triggerPrice,
        buyerCount: buyerCount,
        sellerCount: sellerCount,
        isBigSignal: _isBigSignalSelected,
        isMediumSignal: false,
        isTrap: _isTrapSelected,
        isLiquidation: _isLiquidationSelected,
        isInstitutional: _isInstitutionalSelected,
        bubbleScale: _selectedBubbleScale,
        pulseSpeed: _selectedPulseSpeed,
        bubbleOpacity: _selectedBubbleOpacity,
        createdAt: DateTime.now(),
        adminOnly: _isAdminOnlySelected,
      );

      await ref.read(orderflowServiceProvider).saveGhostOrder(ghost);

      // Inject to suggested similar pattern stocks as well
      if (symbol == 'NIFTY50' && _selectedSimilarStocksToInject.isNotEmpty) {
        for (final suggestSymbol in _selectedSimilarStocksToInject) {
          final int stockBuyer = _randomizeVolumeForSymbol(buyerCount, suggestSymbol);
          final int stockSeller = _randomizeVolumeForSymbol(sellerCount, suggestSymbol);
          final suggestGhost = GhostOrder(
            id: 'GHOST_${DateTime.now().millisecondsSinceEpoch}_$suggestSymbol',
            symbol: suggestSymbol,
            triggerSymbol: 'NIFTY50',
            triggerPrice: triggerPrice,
            buyerCount: stockBuyer,
            sellerCount: stockSeller,
            isBigSignal: _isBigSignalSelected,
            isMediumSignal: false,
            isTrap: _isTrapSelected,
            isLiquidation: _isLiquidationSelected,
            isInstitutional: _isInstitutionalSelected,
            bubbleScale: _selectedBubbleScale,
            pulseSpeed: _selectedPulseSpeed,
            bubbleOpacity: _selectedBubbleOpacity,
            createdAt: DateTime.now(),
            adminOnly: _isAdminOnlySelected,
          );
          await ref.read(orderflowServiceProvider).saveGhostOrder(suggestGhost);
        }
      }

      // Inject ghost to other indices if approved
      if (additionalIndices.isNotEmpty) {
        for (final additionalSymbol in additionalIndices) {
          final int indexBuyer = _randomizeVolumeForSymbol(buyerCount, additionalSymbol);
          final int indexSeller = _randomizeVolumeForSymbol(sellerCount, additionalSymbol);
          final additionalGhost = GhostOrder(
            id: 'GHOST_${DateTime.now().millisecondsSinceEpoch}_$additionalSymbol',
            symbol: additionalSymbol,
            triggerSymbol: 'NIFTY50',
            triggerPrice: triggerPrice,
            buyerCount: indexBuyer,
            sellerCount: indexSeller,
            isBigSignal: _isBigSignalSelected,
            isMediumSignal: false,
            isTrap: _isTrapSelected,
            isLiquidation: _isLiquidationSelected,
            isInstitutional: _isInstitutionalSelected,
            bubbleScale: _selectedBubbleScale,
            pulseSpeed: _selectedPulseSpeed,
            bubbleOpacity: _selectedBubbleOpacity,
            createdAt: DateTime.now(),
            adminOnly: _isAdminOnlySelected,
          );
          await ref.read(orderflowServiceProvider).saveGhostOrder(additionalGhost);
        }
      }
    } else {
      await ref.read(orderflowServiceProvider).saveOrderflow(
        symbol: symbol,
        candleTime: _selectedCandleTime!,
        buyerCount: buyerCount,
        sellerCount: sellerCount,
        isInstitutional: _isInstitutionalSelected,
        isBigSignal: effectiveBigSignal,
        isMediumSignal: false,
        isTrap: _isTrapSelected,
        isLiquidation: _isLiquidationSelected,
        bubbleScale: _selectedBubbleScale,
        pulseSpeed: _selectedPulseSpeed,
        bubbleOpacity: _selectedBubbleOpacity,
        footprint: footprint,
        autoFadeMinutes: _autoFadeMinutes,
        adminOnly: _isAdminOnlySelected,
      );

      // Inject standard to other indices if approved
      if (additionalIndices.isNotEmpty) {
        for (final additionalSymbol in additionalIndices) {
          final int indexBuyer = _randomizeVolumeForSymbol(buyerCount, additionalSymbol);
          final int indexSeller = _randomizeVolumeForSymbol(sellerCount, additionalSymbol);
          await ref.read(orderflowServiceProvider).saveOrderflow(
            symbol: additionalSymbol,
            candleTime: _selectedCandleTime!,
            buyerCount: indexBuyer,
            sellerCount: indexSeller,
            isInstitutional: _isInstitutionalSelected,
            isBigSignal: effectiveBigSignal,
            isMediumSignal: false,
            isTrap: _isTrapSelected,
            isLiquidation: _isLiquidationSelected,
            bubbleScale: _selectedBubbleScale,
            pulseSpeed: _selectedPulseSpeed,
            bubbleOpacity: _selectedBubbleOpacity,
            footprint: footprint,
            autoFadeMinutes: _autoFadeMinutes,
            adminOnly: _isAdminOnlySelected,
          );
        }
      }
    }
    
    // Clear controllers
    _ghostTriggerController.clear();
    _priceLevelController.clear();
    _levelBuyerController.clear();
    _levelSellerController.clear();
    
    final List<String> allSymbols = [symbol];
    if (_isGhostMode && symbol == 'NIFTY50') {
      allSymbols.addAll(_selectedSimilarStocksToInject);
    }
    allSymbols.addAll(additionalIndices);
    
    setState(() {
      _suggestedSimilarStocks = [];
      _selectedSimilarStocksToInject.clear();
      _showOrderflowInput = false;
    });
    
    if (mounted) {
      final String msg = _isGhostMode
          ? 'Level buy/sell orders set for ${allSymbols.join(", ")}!'
          : 'Orderflow saved for ${allSymbols.join(", ")}!';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green),
      );
    }
  }

  Widget _buildInstitutionalToggle() {
    return _buildTacticalToggle(
      icon: Icons.account_balance_rounded,
      label: 'INSTITUTIONAL SIGNAL',
      value: _isInstitutionalSelected,
      onChanged: (v) => setState(() => _isInstitutionalSelected = v),
      activeColor: AppTheme.primaryCyan,
    );
  }

  Widget _buildAdminOnlyToggle() {
    return _buildTacticalToggle(
      icon: Icons.lock_person_rounded,
      label: 'ADMIN ONLY (ADV)',
      value: _isAdminOnlySelected,
      onChanged: (v) => setState(() => _isAdminOnlySelected = v),
      activeColor: Colors.tealAccent,
    );
  }

  Future<void> _handleAutoInjectDaySwings() async {
    final user = ref.read(authProvider).user;
    final isSuperuser = OrderflowService.isSuperuser(user?.email);
    if (!(user?.isAdmin ?? false) && !isSuperuser) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin access required for promo auto-injection.')),
      );
      return;
    }

    final symbol = ref.read(selectedInstrumentProvider);
    final candleState = ref.read(candleStreamProvider);
    final candles = candleState.candles;

    if (candles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No candlestick data available for auto-injection.')),
      );
      return;
    }

    // 1. Group candles by local calendar day (YYYY-MM-DD)
    final Map<String, List<CandleModel>> candlesByDay = {};
    for (final c in candles) {
      final local = c.timeStart.toLocal();
      final dayKey = '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
      candlesByDay.putIfAbsent(dayKey, () => []).add(c);
    }

    if (candlesByDay.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid candles found for swing analysis.')),
      );
      return;
    }

    // 2. Select the target trading day session (the most recent day key with at least 2 candles)
    final sortedDayKeys = candlesByDay.keys.toList()..sort();
    String? targetDayKey;
    for (int i = sortedDayKeys.length - 1; i >= 0; i--) {
      if (candlesByDay[sortedDayKeys[i]]!.length >= 2) {
        targetDayKey = sortedDayKeys[i];
        break;
      }
    }
    targetDayKey ??= sortedDayKeys.last;

    final List<CandleModel> dayCandles = candlesByDay[targetDayKey]!;

    if (dayCandles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not enough candles available for swing calculation.')),
      );
      return;
    }

    // 3. Find the exact Swing Low candle and Swing High candle for the entire day's session
    CandleModel lowestCandle = dayCandles.reduce((curr, next) => next.low < curr.low ? next : curr);
    CandleModel highestCandle = dayCandles.reduce((curr, next) => next.high > curr.high ? next : curr);

    // Calculate up move vs down move relative to session open to choose dominant single swing
    final firstCandleOpen = dayCandles.first.open;
    final upMove = (highestCandle.high - firstCandleOpen).abs();
    final downMove = (firstCandleOpen - lowestCandle.low).abs();

    String injectionSummary = '';
    final orderflowService = ref.read(orderflowServiceProvider);

    if (upMove >= downMove) {
      // Inject ONLY SELLER at Day High / Swing High Candle
      final sellerVol = 4450 + (DateTime.now().millisecondsSinceEpoch % 700);
      final buyerHighVol = 310 + (DateTime.now().millisecondsSinceEpoch % 130);
      await orderflowService.saveOrderflow(
        symbol: symbol,
        candleTime: highestCandle.timeStart,
        buyerCount: buyerHighVol,
        sellerCount: sellerVol,
        isInstitutional: true,
        isBigSignal: true,
        isMediumSignal: false,
        isTrap: false,
        isLiquidation: false,
        bubbleScale: 5.0,
        pulseSpeed: 1.0,
        bubbleOpacity: 0.95,
        footprint: {
          highestCandle.high: PriceLevelData(
            buyVolume: buyerHighVol,
            sellVolume: sellerVol,
          )
        },
        customTag: "",
        autoFadeMinutes: 0,
        adminOnly: true,
      );
      final highTimeStr = intl.DateFormat('hh:mm a').format(highestCandle.timeStart.toLocal());
      injectionSummary = '⚡ SINGLE INJECTION PROMO ($targetDayKey):\n\n'
          '• SELLER Signal @ Swing High (₹${highestCandle.high.toStringAsFixed(1)} at $highTimeStr)';
    } else {
      // Inject ONLY BUYER at Day Low / Swing Low Candle
      final buyerVol = 4250 + (DateTime.now().millisecondsSinceEpoch % 650);
      final sellerLowVol = 280 + (DateTime.now().millisecondsSinceEpoch % 120);
      await orderflowService.saveOrderflow(
        symbol: symbol,
        candleTime: lowestCandle.timeStart,
        buyerCount: buyerVol,
        sellerCount: sellerLowVol,
        isInstitutional: true,
        isBigSignal: true,
        isMediumSignal: false,
        isTrap: false,
        isLiquidation: false,
        bubbleScale: 5.0,
        pulseSpeed: 1.0,
        bubbleOpacity: 0.95,
        footprint: {
          lowestCandle.low: PriceLevelData(
            buyVolume: buyerVol,
            sellVolume: sellerLowVol,
          )
        },
        customTag: "",
        autoFadeMinutes: 0,
        adminOnly: true,
      );
      final lowTimeStr = intl.DateFormat('hh:mm a').format(lowestCandle.timeStart.toLocal());
      injectionSummary = '⚡ SINGLE INJECTION PROMO ($targetDayKey):\n\n'
          '• BUYER Signal @ Swing Low (₹${lowestCandle.low.toStringAsFixed(1)} at $lowTimeStr)';
    }

    // Refresh candle stream so injected signals immediately illuminate on the chart
    ref.read(candleStreamProvider.notifier).refresh();

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF131722),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppTheme.goldColor, width: 1.5),
          ),
          title: Row(
            children: [
              const Icon(Icons.bolt_rounded, color: AppTheme.goldColor, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'PROMO AUTO-INJECT SUCCESS ($symbol)',
                  style: const TextStyle(
                    color: AppTheme.goldColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            injectionSummary,
            style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.goldColor,
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('GREAT', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
  }



  Widget _buildBigSignalToggle() {
    return _buildTacticalToggle(
      icon: Icons.stars_rounded,
      label: 'BIG SIGNAL',
      value: _isBigSignalSelected,
      onChanged: (v) => setState(() {
        _isBigSignalSelected = v;
        if (v) {

          _isTrapSelected = false;
          _isLiquidationSelected = false;
        }
      }),
      activeColor: AppTheme.goldColor,
    );
  }

  Widget _buildTrapToggle() {
    return _buildTacticalToggle(
      icon: Icons.dangerous_rounded,
      label: 'TRAP SIGNAL',
      value: _isTrapSelected,
      onChanged: (v) => setState(() {
        _isTrapSelected = v;
        if (v) {
          _isBigSignalSelected = false;

          _isLiquidationSelected = false;
        }
      }),
      activeColor: Colors.orangeAccent,
    );
  }

  Widget _buildLiquidationToggle() {
    return _buildTacticalToggle(
      icon: Icons.flash_on_rounded,
      label: 'LIQUIDATION',
      value: _isLiquidationSelected,
      onChanged: (v) => setState(() {
        _isLiquidationSelected = v;
        if (v) {
          _isBigSignalSelected = false;

          _isTrapSelected = false;
        }
      }),
      activeColor: Colors.purpleAccent,
    );
  }

  Widget _buildTacticalToggle({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color activeColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: value ? activeColor.withValues(alpha: 0.3) : Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: value ? activeColor : Colors.white38, size: 16),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SizedBox(
            height: 24,
            child: Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeTrackColor: activeColor.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(DateTime? lastUpdated) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            top: 8,
            bottom: 8 + MediaQuery.of(context).padding.bottom,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.access_time_rounded, color: AppTheme.dimTextColor, size: 12 * _scaleFactor),
                  const SizedBox(width: 4),
                  Text(
                    'SYNCED: ${lastUpdated != null ? intl.DateFormat('hh:mm:ss a').format(lastUpdated) : '--'}',
                    style: TextStyle(color: AppTheme.dimTextColor, fontSize: 9 * _scaleFactor, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                ],
              ),
              // Timeframe Indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryCyan.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppTheme.primaryCyan.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.query_stats_rounded, color: AppTheme.primaryCyan, size: 10 * _scaleFactor),
                    const SizedBox(width: 4),
                    Text(
                      '5 MIN',
                      style: TextStyle(
                        color: AppTheme.primaryCyan,
                        fontSize: 8 * _scaleFactor,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 6 * _scaleFactor, height: 6 * _scaleFactor,
                    decoration: const BoxDecoration(color: AppTheme.primaryCyan, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  if (!_isSmallDevice)
                    Text(
                      'INSTITUTIONAL FEED ACTIVE',
                      style: TextStyle(color: AppTheme.primaryCyan, fontSize: 9 * _scaleFactor, fontWeight: FontWeight.w900, letterSpacing: 1),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReplayControlPanel(CandleStreamState candleState) {
    final notifier = ref.read(candleStreamProvider.notifier);
    final total = candleState.replayCandles.length;
    final current = candleState.replayIndex + 1;
    final isPaused = candleState.isReplayPaused;
    final speed = candleState.replaySpeed;

    return Positioned(
      bottom: 24,
      left: 16,
      right: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.8), // Rich Dark Slate
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppTheme.primaryCyan.withValues(alpha: 0.25),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryCyan.withValues(alpha: 0.15),
                  blurRadius: 25,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Timeline Slider Row
                Row(
                  children: [
                    // Info Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryCyan.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.primaryCyan.withValues(alpha: 0.25), width: 0.8),
                      ),
                      child: Text(
                        '$current / $total',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          activeTrackColor: AppTheme.primaryCyan,
                          inactiveTrackColor: Colors.white10,
                          thumbColor: AppTheme.primaryCyan,
                          overlayColor: AppTheme.primaryCyan.withValues(alpha: 0.15),
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                        ),
                        child: Slider(
                          min: 0,
                          max: (total - 1).toDouble(),
                          value: (current - 1).toDouble().clamp(0, (total - 1).toDouble()),
                          onChanged: (val) {
                            HapticFeedback.selectionClick();
                            notifier.seekReplay(val.toInt());
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Buttons Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Playback Status Indicator
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isPaused ? Colors.amber : const Color(0xFF00FF41),
                            boxShadow: [
                              BoxShadow(
                                color: (isPaused ? Colors.amber : const Color(0xFF00FF41)).withValues(alpha: 0.5),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isPaused ? 'PAUSED' : 'PLAYING',
                          style: TextStyle(
                            color: isPaused ? Colors.amber : const Color(0xFF00FF41),
                            fontWeight: FontWeight.w900,
                            fontSize: 8,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    
                    // Center Controls: Skip Prev, Play/Pause, Skip Next
                    Row(
                      children: [
                        // Skip Backward (Step Prev)
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: isPaused
                                ? () {
                                    HapticFeedback.lightImpact();
                                    notifier.stepBackwardReplay();
                                  }
                                : null,
                            borderRadius: BorderRadius.circular(30),
                            child: Opacity(
                              opacity: isPaused ? 1.0 : 0.4,
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.06),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: const Icon(
                                  Icons.skip_previous_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        
                        // Play/Pause Action
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              if (isPaused) {
                                notifier.resumeReplay();
                              } else {
                                notifier.pauseReplay();
                              }
                            },
                            borderRadius: BorderRadius.circular(30),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.primaryCyan,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.primaryCyan.withValues(alpha: 0.35),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Icon(
                                isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                                color: AppTheme.bgColor,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Step Forward (Skip Next)
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: isPaused
                                ? () {
                                    HapticFeedback.lightImpact();
                                    notifier.stepReplay();
                                  }
                                : null,
                            borderRadius: BorderRadius.circular(30),
                            child: Opacity(
                              opacity: isPaused ? 1.0 : 0.4,
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.06),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: const Icon(
                                  Icons.skip_next_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Right Controls: Speed and Exit
                    Row(
                      children: [
                        // Speed Selector Chip
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _showSpeedSelector(context, speed, notifier);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.speed_rounded, color: AppTheme.goldColor, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  '${speed}X',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Exit Button
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              notifier.exitReplay();
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.bearColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppTheme.bearColor.withValues(alpha: 0.35)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.close_rounded, color: AppTheme.bearColor, size: 12),
                                  SizedBox(width: 3),
                                  Text(
                                    'EXIT',
                                    style: TextStyle(
                                      color: AppTheme.bearColor,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                    ),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSpeedSelector(BuildContext context, int currentSpeed, CandleStreamNotifier notifier) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.95),
              border: Border(
                top: BorderSide(
                  color: AppTheme.primaryCyan.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SELECT PLAYBACK SPEED',
                  style: TextStyle(
                    color: AppTheme.primaryCyan,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [1, 2, 3, 5].map((s) {
                    final isSelected = currentSpeed == s;
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        notifier.setReplaySpeed(s);
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: 60,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isSelected 
                              ? AppTheme.primaryCyan.withValues(alpha: 0.2) 
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? AppTheme.primaryCyan : Colors.white12,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '${s}X',
                            style: TextStyle(
                              color: isSelected ? AppTheme.primaryCyan : Colors.white70,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }



  Future<void> _updateScreenshotProtection(bool isAdmin, [bool? allowAdminScreenshots]) async {
    // 1. Web & Desktop Safety: These platforms don't support or need this plugin
    if (kIsWeb) return;
    
    // Explicit platform check for Android/iOS only
    final bool isMobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    if (!isMobile) return;

    try {
      // Small delay to ensure the screen has fully transitioned
      await Future.delayed(const Duration(milliseconds: 250));

      try {
        // Screenshot protection is globally removed
        await ScreenSecure.disableScreenshotBlock();
        await ScreenSecure.disableScreenRecordBlock();
        debugPrint("[SCREEN_PROTECT] Protection DISABLED globally");
      } on MissingPluginException {
        // Silently ignore - common on certain flavored builds or emulators
      } catch (e) {
        debugPrint("[SCREEN_PROTECT] Non-critical error: $e");
      }
    } catch (e) {
      // Global safety
    }
  }

  String _getShortUid() {
    try {
      final user = ref.read(authProvider).user;
      if (user == null) return 'GUEST';
      final uid = user.uid;
      if (uid.length >= 4) {
        return uid.substring(uid.length - 4).toUpperCase();
      }
      return uid.toUpperCase();
    } catch (_) {
      return 'USER';
    }
  }


  Future<void> _openStockSearch({bool isIndexOnly = false}) async {
    final selected = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dialogCtx) => StockSearchDialog(isIndexOnly: isIndexOnly),
    );
    if (selected != null && mounted) {
      _triggerSearchTransition(selected);
    }
  }

  void _triggerSearchTransition(String symbol) {
    if (mounted) {
      ref.read(selectedInstrumentProvider.notifier).state = symbol;
    }
  }

  Widget _buildTransitionOverlay() {
    if (!_isSearchingTransition || _transitionSymbol == null) {
      return const SizedBox.shrink();
    }

    final symbol = _transitionSymbol!;
    final name = AppConstants.instrumentNames[symbol] ?? symbol;

    return Positioned.fill(
      child: Container(
        color: AppTheme.bgColor.withValues(alpha: 0.95),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(seconds: 2),
                  builder: (context, value, child) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryCyan.withValues(alpha: 0.2 * value),
                            blurRadius: 30,
                            spreadRadius: 10 * value,
                          ),
                        ],
                        border: Border.all(
                          color: AppTheme.primaryCyan.withValues(alpha: 0.3 * value),
                          width: 1.5,
                        ),
                      ),
                      child: child,
                    );
                  },
                  child: Hero(
                    tag: 'logo_transition_${DateTime.now().millisecondsSinceEpoch}',
                    child: _buildInstrumentLogo(symbol, size: 70),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  name.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'ANALYZING ORDERFLOW FOR $symbol...',
                  style: TextStyle(
                    color: AppTheme.primaryCyan.withValues(alpha: 0.8),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: 120,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryCyan),
                      minHeight: 2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMaintenanceOverlay() {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: AppTheme.bgColor.withValues(alpha: 0.8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.bearColor.withValues(alpha: 0.1),
                border: Border.all(color: AppTheme.bearColor.withValues(alpha: 0.2), width: 2),
              ),
              child: const Icon(Icons.engineering_rounded, size: 80, color: AppTheme.bearColor),
            ),
            const SizedBox(height: 32),
            const Text(
              'WORKING ON SERVER',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'SYSTEM IS UNDERGOING PERFORMANCE OPTIMIZATION.\nPLEASE STAND BY FOR RE-ACTIVATION.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.dimTextColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 48),
            _buildLoadingLogo(),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, size: 40, color: AppTheme.bearColor),
          const SizedBox(height: 16),
          const Text(
            'CONNECTION TERMINATED',
            style: TextStyle(color: AppTheme.bearColor, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 2),
          ),
          const SizedBox(height: 8),
          Text(
            error, 
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.dimTextColor, fontSize: 11),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => ref.read(candleStreamProvider.notifier).refresh(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryCyan,
              foregroundColor: AppTheme.bgColor,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: const Text('RE-ESTABLISH UPLINK', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyWidget(CandleStreamState state) {
    final isAdmin = ref.read(authProvider).user?.isAdmin ?? false;
    
    String message = 'INITIALIZING QUANTUM FEED...';
    String subMessage = 'Establishing connection to high-frequency nodes...';
    
    if (!state.isLoading) {
      if (state.isOffline) {
        message = 'UPLINK DISCONNECTED';
        subMessage = 'Network restricted or WebSocket handshake failed.';
      } else {
        message = 'SYNCING DATA PIPELINE...';
        subMessage = 'Historical sequence empty. Re-seeding from cluster...';
      }
    } else if (state.candles.isEmpty) {
      message = 'SYNCING DATA PIPELINE...';
      subMessage = 'Re-seeding from cluster...';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (state.isLoading)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: _buildLoadingLogo(),
            )
          else
            const Padding(
              padding: EdgeInsets.only(bottom: 24),
              child: Icon(Icons.cloud_off_rounded, color: AppTheme.errorColor, size: 40),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              children: [
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    letterSpacing: 3,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.primaryCyan.withValues(alpha: 0.6),
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          
          if (state.isLoading) ...[
            const SizedBox(
              width: 280,
              child: ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(2)),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryCyan),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'CLUSTERING REAL-TIME NODES: ${state.candles.length}',
              style: TextStyle(
                color: AppTheme.primaryCyan.withValues(alpha: 0.4),
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ] else ...[
            // Recovery Buttons
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildActionChip(
                  label: 'HARD BOOTSTRAP',
                  icon: Icons.refresh_rounded,
                  onTap: () async {
                    await ref.read(candleStreamProvider.notifier).refresh(clearCache: true);
                  },
                  color: AppTheme.primaryCyan,
                ),
                const SizedBox(width: 16),

              ],
            ),
          ],
          
          const SizedBox(height: 60),
          // Admin Debug Info
          if (OrderflowService.isSuperuser(ref.read(authProvider).user?.email))
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.symmetric(horizontal: 40),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  const Text('ADMIN DIAGNOSTICS', style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _debugRow('Source', state.dataSourceInfo ?? 'UNKNOWN'),
                  _debugRow('IsLoading', state.isLoading.toString()),
                  _debugRow('CandleCount', state.candles.length.toString()),
                  _debugRow('LastUpdate', state.lastUpdated?.toString() ?? 'NEVER'),
                  _debugRow('Connection', state.isOffline ? 'OFFLINE' : 'CONNECTED'),
                ],
              ),
            ),
        ],
      ),
    );
  }



  Widget _buildAnimatedEntry({required Widget child, required int delayMs}) {
    final start = delayMs / 1000;
    final end = (delayMs + 400) / 1000;
    
    return AnimatedBuilder(
      animation: _entryController,
      builder: (context, child) {
        final animValue = Interval(
          start.clamp(0.0, 1.0), 
          end.clamp(0.0, 1.0), 
          curve: Curves.easeOutCubic
        ).transform(_entryController.value);

        return Opacity(
          opacity: animValue,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - animValue)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  // --- HELPERS ---

  Widget _buildLoadingLogo() {
    return const FuturisticRadarLoader(size: 130);
  }

  Widget _debugRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white24, fontSize: 10)),
          Text(value, style: const TextStyle(color: Colors.white60, fontSize: 10, fontFamily: 'Monospace')),
        ],
      ),
    );
  }

  Widget _buildActionChip({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  int _randomizeVolumeForSymbol(int base, String symbol) {
    if (base <= 0) return 0;
    final random = math.Random();
    
    // Check if symbol is an index
    final bool isIndex = NiftyStocks.indices.containsKey(symbol.toUpperCase());
    
    // Scale factor: indices 60% to 140%, stocks 20% to 120%
    final double scale = isIndex 
        ? (0.6 + random.nextDouble() * 0.8) 
        : (0.2 + random.nextDouble() * 1.0);
        
    int scaledBase = (base * scale).round();
    if (scaledBase <= 0) scaledBase = 10;
    
    // Apply 15% random variance
    final variance = (scaledBase * 0.15).toInt();
    if (variance == 0) return scaledBase;
    
    final change = random.nextInt(variance * 2 + 1) - variance;
    int result = scaledBase + change;
    
    // Avoid multiples of 10 for organic look
    if (result % 10 == 0) {
      result += random.nextInt(9) + 1;
    }
    return result;
  }
}





class LiveCandlePulse extends StatefulWidget {
  final Color color;
  const LiveCandlePulse({super.key, required this.color});

  @override
  State<LiveCandlePulse> createState() => _LiveCandlePulseState();
}

class _LiveCandlePulseState extends State<LiveCandlePulse> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseScale;
  late Animation<double> _pulseOpacity;
  late Animation<double> _rippleScale;
  late Animation<double> _rippleOpacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();

    _pulseScale = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _pulseOpacity = Tween<double>(begin: 0.8, end: 0.2).animate(_controller);

    _rippleScale = Tween<double>(begin: 0.8, end: 2.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _rippleOpacity = Tween<double>(begin: 0.95, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // 1. Expanding Repainting Shockwave Ripple Ring
            Transform.scale(
              scale: _rippleScale.value,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.color.withValues(alpha: _rippleOpacity.value),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            // 2. Glowing Core Pulse Aura
            Transform.scale(
              scale: _pulseScale.value,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: _pulseOpacity.value),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.8),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
            // 3. Bright Core Laser Dot
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }
}


class StockSearchDialog extends StatefulWidget {
  final bool isIndexOnly;
  const StockSearchDialog({super.key, this.isIndexOnly = false});

  @override
  State<StockSearchDialog> createState() => _StockSearchDialogState();
}

class _StockSearchDialogState extends State<StockSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    var history = prefs.getStringList('search_history') ?? [];
    if (widget.isIndexOnly) {
      history = history.where((s) => NiftyStocks.isIndexOnlyAllowed(s)).toList();
    }
    if (mounted) {
      setState(() => _history = history);
    }
  }

  Future<void> _saveToHistory(String symbol) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('search_history') ?? [];
    history.remove(symbol);
    history.insert(0, symbol);
    if (history.length > 5) {
      history = history.sublist(0, 5);
    }
    await prefs.setStringList('search_history', history);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = widget.isIndexOnly
        ? NiftyStocks.searchIndicesOnly(_query)
        : NiftyStocks.search(_query);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: GestureDetector(
          onTap: () {}, // Absorb taps inside search window
          child: Center(
            child: Container(
              width: math.min(MediaQuery.of(context).size.width * 0.9, 520),
          constraints: const BoxConstraints(maxHeight: 520),
          decoration: BoxDecoration(
            color: const Color(0xFF0E1824).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primaryCyan.withValues(alpha: 0.4), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryCyan.withValues(alpha: 0.15),
                blurRadius: 24,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.8),
                blurRadius: 32,
                spreadRadius: 8,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Search Input Header
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: AppTheme.primaryCyan, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          hintText: widget.isIndexOnly
                              ? 'Search NIFTY50, BANKNIFTY, FINNIFTY...'
                              : 'Search Nifty 50 stocks (e.g. RELIANCE, TCS)...',
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onChanged: (val) => setState(() => _query = val.trim()),
                      ),
                    ),
                    if (_query.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10, height: 1),
              // Search Results / History List
              Flexible(
                child: _query.isEmpty
                    ? (_history.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Center(
                              child: Text(
                                widget.isIndexOnly
                                    ? 'Search: NIFTY50, BANKNIFTY, FINNIFTY, SENSEX'
                                    : 'Search Nifty 50 stocks',
                                style: const TextStyle(color: Colors.white38, fontSize: 12),
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _history.length,
                            itemBuilder: (context, index) {
                              final symbol = _history[index];
                              final name = NiftyStocks.stocks[symbol] ??
                                  NiftyStocks.indexOnlySymbols[symbol] ?? symbol;
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.history_rounded, color: AppTheme.primaryCyan, size: 18),
                                title: Text(symbol, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                subtitle: Text(name, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                                onTap: () {
                                  _saveToHistory(symbol);
                                  Navigator.pop(context, symbol);
                                },
                              );
                            },
                          ))
                    : (results.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(32.0),
                            child: Center(
                              child: Text('No stocks found matching query', style: TextStyle(color: Colors.white38, fontSize: 12)),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: results.length,
                            itemBuilder: (context, index) {
                              final symbol = results.keys.elementAt(index);
                              final name = results.values.elementAt(index);
                              return ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: AppTheme.primaryCyan.withValues(alpha: 0.15),
                                  child: Text(
                                    symbol.isNotEmpty ? symbol[0] : 'S',
                                    style: const TextStyle(color: AppTheme.primaryCyan, fontWeight: FontWeight.w900, fontSize: 11),
                                  ),
                                ),
                                title: Text(symbol, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                                subtitle: Text(name, style: const TextStyle(color: Colors.white54, fontSize: 10)),
                                onTap: () {
                                  _saveToHistory(symbol);
                                  Navigator.pop(context, symbol);
                                },
                              );
                            },
                          )),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);
  }
}

class StockSearchDelegate extends SearchDelegate<String?> {
  final bool isIndexOnly;

  StockSearchDelegate({this.isIndexOnly = false});

  static const String _historyKey = 'search_history';

  static Future<void> _saveToHistory(String symbol) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList(_historyKey) ?? [];
    history.remove(symbol);
    history.insert(0, symbol);
    if (history.length > 5) {
      history = history.sublist(0, 5);
    }
    await prefs.setStringList(_historyKey, history);
  }

  @override
  ThemeData appBarTheme(BuildContext context) {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xFF060B12),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0E1824),
        elevation: 0,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
        hintStyle: TextStyle(color: Colors.white54),
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      )
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, null);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSuggestionsList(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSuggestionsList(context);
  }

  Widget _buildSuggestionsList(BuildContext context) {
    if (query.isEmpty) {
      // Show History (filter to index-only if restricted)
      return FutureBuilder<SharedPreferences>(
        future: SharedPreferences.getInstance(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          var history = snapshot.data!.getStringList(_historyKey) ?? [];
          if (isIndexOnly) {
            history = history
                .where((s) => NiftyStocks.isIndexOnlyAllowed(s))
                .toList();
          }
          if (history.isEmpty) {
            return Center(
              child: Text(
                isIndexOnly
                    ? 'Search: NIFTY50, BANKNIFTY, FINNIFTY, SENSEX'
                    : 'Search Nifty 50 stocks',
                style: const TextStyle(color: Colors.white54),
              ),
            );
          }
          return ListView.builder(
            itemCount: history.length,
            itemBuilder: (context, index) {
              final symbol = history[index];
              final name = NiftyStocks.stocks[symbol] ??
                  NiftyStocks.indexOnlySymbols[symbol] ?? symbol;
              return ListTile(
                leading: const Icon(Icons.history, color: Colors.white54),
                title: Text(symbol, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                subtitle: Text(name, style: const TextStyle(color: Colors.white54)),
                onTap: () {
                  _saveToHistory(symbol);
                  close(context, symbol);
                },
              );
            },
          );
        },
      );
    }

    // Search results — restrict to index-only symbols if needed
    final results = isIndexOnly
        ? NiftyStocks.searchIndicesOnly(query)
        : NiftyStocks.search(query);
    if (results.isEmpty) {
      return const Center(child: Text('No stocks found.', style: TextStyle(color: Colors.white54)));
    }
    
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final symbol = results.keys.elementAt(index);
        final name = results.values.elementAt(index);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF00BCD4).withOpacity(0.1),
            child: Text(symbol.isNotEmpty ? symbol[0] : 'S', style: const TextStyle(color: Color(0xFF00BCD4), fontWeight: FontWeight.bold)),
          ),
          title: Text(symbol, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          subtitle: Text(name, style: const TextStyle(color: Colors.white54)),
          onTap: () {
            _saveToHistory(symbol);
            close(context, symbol);
          },
        );
      },
    );
  }
}

// ─── ADMIN GLOWING ORB VISUAL ───

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

class _InstrumentLogoWithFallback extends StatefulWidget {
  final String primaryUrl;
  final String fallbackUrl;
  final double size;
  final Widget defaultWidget;

  const _InstrumentLogoWithFallback({
    required this.primaryUrl,
    required this.fallbackUrl,
    required this.size,
    required this.defaultWidget,
  });

  @override
  State<_InstrumentLogoWithFallback> createState() => _InstrumentLogoWithFallbackState();
}

class _InstrumentLogoWithFallbackState extends State<_InstrumentLogoWithFallback> {
  bool _primaryFailed = false;
  bool _fallbackFailed = false;

  @override
  void didUpdateWidget(_InstrumentLogoWithFallback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.primaryUrl != widget.primaryUrl) {
      setState(() {
        _primaryFailed = false;
        _fallbackFailed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_fallbackFailed) return widget.defaultWidget;

    final url = _primaryFailed ? widget.fallbackUrl : widget.primaryUrl;
    if (url.isEmpty) return widget.defaultWidget;

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.size * 0.5),
      child: Image.network(
        url,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: widget.size,
            height: widget.size,
            alignment: Alignment.center,
            child: SizedBox(
              width: widget.size * 0.5,
              height: widget.size * 0.5,
              child: const CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BCD4)),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          if (!_primaryFailed) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _primaryFailed = true);
            });
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _fallbackFailed = true);
            });
          }
          return Container(
            width: widget.size,
            height: widget.size,
            decoration: const BoxDecoration(
              color: Color(0xFF0C1420),
              shape: BoxShape.circle,
            ),
          );
        },
      ),
    );
  }
}

Widget _buildRadarMiniLogo(String symbol) {
  final cleanSymbol = StockLogos.cleanSymbol(symbol);

  // Gradient monogram fallback — shown when no network logo is available
  Widget monogramFallback = _buildSymbolMonogram(cleanSymbol, size: 16);

  if (StockLogos.localAssets.containsKey(cleanSymbol)) {
    return ClipOval(
      child: Image.asset(
        StockLogos.localAssets[cleanSymbol]!,
        fit: BoxFit.cover,
        width: 16,
        height: 16,
        errorBuilder: (context, error, stackTrace) => monogramFallback,
      ),
    );
  }

  if (StockLogos.domains.containsKey(cleanSymbol)) {
    return _InstrumentLogoWithFallback(
      primaryUrl: StockLogos.getLogoUrl(cleanSymbol),
      fallbackUrl: StockLogos.getFallbackLogoUrl(cleanSymbol),
      size: 16,
      defaultWidget: monogramFallback,
    );
  }

  // Unknown symbol — show monogram
  return monogramFallback;
}

/// Generates a colored gradient circle with the stock's initials.
Widget _buildSymbolMonogram(String symbol, {double size = 16}) {
  // Pick deterministic color based on symbol hash
  final colors = [
    [const Color(0xFF00B4D8), const Color(0xFF0077B6)],
    [const Color(0xFF06D6A0), const Color(0xFF118AB2)],
    [const Color(0xFFFFD166), const Color(0xFFEF476F)],
    [const Color(0xFF8338EC), const Color(0xFF3A86FF)],
    [const Color(0xFFFF6B6B), const Color(0xFFEE00FF)],
    [const Color(0xFF43AA8B), const Color(0xFF277DA1)],
    [const Color(0xFFF9C74F), const Color(0xFFF3722C)],
    [const Color(0xFF90BE6D), const Color(0xFF43AA8B)],
  ];
  final idx = symbol.codeUnits.fold(0, (prev, c) => prev + c) % colors.length;
  final pair = colors[idx];
  final label = symbol.length >= 3 ? symbol.substring(0, 3) : symbol;
  final fontSize = size * 0.30;

  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        colors: pair,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Center(
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.3,
          height: 1,
        ),
      ),
    ),
  );
}


class RadarVisualizerFixed extends ConsumerStatefulWidget {
  const RadarVisualizerFixed({super.key});

  @override
  ConsumerState<RadarVisualizerFixed> createState() => _RadarVisualizerFixedState();
}

class _RadarVisualizerFixedState extends ConsumerState<RadarVisualizerFixed> with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;
  final math.Random _random = math.Random();
  int _rotationCount = 0;
  double _lastValue = 0.0;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    _rotationController.addListener(() {
      if (!mounted) return;
      final double currentValue = _rotationController.value;
      if (currentValue < _lastValue) {
        setState(() {
          _rotationCount++;
        });
      }
      _lastValue = currentValue;
    });
    _rotationController.repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  static final List<Offset> _radarSlots = [
    // Inner track (Radius 32)
    Offset(math.cos(0 * math.pi / 180) * 32, math.sin(0 * math.pi / 180) * 32),
    Offset(math.cos(120 * math.pi / 180) * 32, math.sin(120 * math.pi / 180) * 32),
    Offset(math.cos(240 * math.pi / 180) * 32, math.sin(240 * math.pi / 180) * 32),
    
    // Middle track (Radius 60)
    Offset(math.cos(45 * math.pi / 180) * 60, math.sin(45 * math.pi / 180) * 60),
    Offset(math.cos(135 * math.pi / 180) * 60, math.sin(135 * math.pi / 180) * 60),
    Offset(math.cos(225 * math.pi / 180) * 60, math.sin(225 * math.pi / 180) * 60),
    Offset(math.cos(315 * math.pi / 180) * 60, math.sin(315 * math.pi / 180) * 60),
    
    // Outer track (Radius 84)
    Offset(math.cos(15 * math.pi / 180) * 84, math.sin(15 * math.pi / 180) * 84),
    Offset(math.cos(87 * math.pi / 180) * 84, math.sin(87 * math.pi / 180) * 84),
    Offset(math.cos(159 * math.pi / 180) * 84, math.sin(159 * math.pi / 180) * 84),
    Offset(math.cos(231 * math.pi / 180) * 84, math.sin(231 * math.pi / 180) * 84),
    Offset(math.cos(303 * math.pi / 180) * 84, math.sin(303 * math.pi / 180) * 84),
  ];

  double _getBlipAngleForIndex(int index) {
    if (index >= 0 && index < 3) {
      return (index * 120) * math.pi / 180;
    } else if (index >= 3 && index < 7) {
      return ((index - 3) * 90 + 45) * math.pi / 180;
    } else {
      return ((index - 7) * 72 + 15) * math.pi / 180;
    }
  }

  double _getBlipOpacityByAngle(double blipAngle, double sweepAngle) {
    double diff = (sweepAngle - blipAngle) % (2 * math.pi);
    if (diff < 2.0) {
      return 0.35 + (0.65 * (1.0 - (diff / 2.0)));
    }
    return 0.35;
  }

  @override
  Widget build(BuildContext context) {
    final signalsAsync = ref.watch(globalSignalsProvider);
    final List<Map<String, dynamic>> signals = signalsAsync.value ?? [];
    
    final List<Map<String, dynamic>> activeTargets = signals.isNotEmpty
        ? signals
        : [
            {
              'symbol': AppConstants.nifty50,
              'buyerCount': 120,
              'sellerCount': 30,
            },
            {
              'symbol': AppConstants.bankNifty,
              'buyerCount': 40,
              'sellerCount': 150,
            },
            {
              'symbol': 'TCS',
              'buyerCount': 90,
              'sellerCount': 10,
            }
          ];

    final int totalStocks = activeTargets.length;
    final int itemsPerPage = 12;
    List<Map<String, dynamic>> visibleTargets = [];
    if (totalStocks <= itemsPerPage) {
      visibleTargets = activeTargets;
    } else {
      final int totalPages = (totalStocks / itemsPerPage).ceil();
      final int currentPage = _rotationCount % totalPages;
      final int startIndex = currentPage * itemsPerPage;
      final int endIndex = math.min(startIndex + itemsPerPage, totalStocks);
      visibleTargets = activeTargets.sublist(startIndex, endIndex);
    }

    const double centerOffset = 110.0;

    return Container(
      height: 235,
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Concentric circles with tech colors
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF00FF66).withValues(alpha: 0.15),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00FF66).withValues(alpha: 0.02),
                  blurRadius: 15,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF00FF66).withValues(alpha: 0.08),
                width: 1,
              ),
            ),
          ),
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF00FF66).withValues(alpha: 0.06),
                width: 1,
              ),
            ),
          ),
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF00FF66).withValues(alpha: 0.04),
                width: 1,
              ),
            ),
          ),
          
          // Radar crosshairs
          Container(
            width: 220,
            height: 1,
            color: const Color(0xFF00FF66).withValues(alpha: 0.05),
          ),
          Container(
            width: 1,
            height: 220,
            color: const Color(0xFF00FF66).withValues(alpha: 0.05),
          ),

          // Radar degrees text
          Positioned(
            top: 8,
            child: Text('000° N', style: TextStyle(color: const Color(0xFF00FF66).withValues(alpha: 0.4), fontSize: 6, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          ),
          Positioned(
            right: 8,
            child: Text('090° E', style: TextStyle(color: const Color(0xFF00FF66).withValues(alpha: 0.4), fontSize: 6, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          ),
          Positioned(
            bottom: 8,
            child: Text('180° S', style: TextStyle(color: const Color(0xFF00FF66).withValues(alpha: 0.4), fontSize: 6, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          ),
          Positioned(
            left: 8,
            child: Text('270° W', style: TextStyle(color: const Color(0xFF00FF66).withValues(alpha: 0.4), fontSize: 6, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          ),

          // Range indicators
          Positioned(top: centerOffset - 50, child: Text('50m', style: TextStyle(color: const Color(0xFF00FF66).withValues(alpha: 0.25), fontSize: 5, fontFamily: 'monospace'))),
          Positioned(top: centerOffset - 80, child: Text('100m', style: TextStyle(color: const Color(0xFF00FF66).withValues(alpha: 0.25), fontSize: 5, fontFamily: 'monospace'))),

          // Center blinking transmitter dot
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFF00FF66),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Color(0xFF00FF66), blurRadius: 6, spreadRadius: 1.5),
              ],
            ),
          ),

          // Rotating Sweep Gradient
          RotationTransition(
            turns: _rotationController,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    const Color(0xFF00FF66).withValues(alpha: 0.3),
                    const Color(0xFF00FF66).withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.35, 1.0],
                ),
              ),
            ),
          ),

          // Rotating Lead Sweep Line (high intensity)
          AnimatedBuilder(
            animation: _rotationController,
            builder: (context, child) {
              final double angle = _rotationController.value * 2 * math.pi;
              return Transform.rotate(
                angle: angle - math.pi / 2,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    width: 1.5,
                    height: 110,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF00FF66),
                          const Color(0xFF00FF66).withValues(alpha: 0.05),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00FF66).withValues(alpha: 0.8),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          // Target stock blips overlayed
          ...visibleTargets.asMap().entries.map((entry) {
            final int idx = entry.key;
            final Map<String, dynamic> target = entry.value;
            final String symbol = target['symbol'] ?? '';
            final int buyerCount = target['buyerCount'] ?? 0;
            final int sellerCount = target['sellerCount'] ?? 0;
            final bool isBuy = buyerCount >= sellerCount;
            final Color signalColor = isBuy ? AppTheme.bullColor : AppTheme.bearColor;
            final Offset offset = idx < _radarSlots.length ? _radarSlots[idx] : Offset.zero;
            final double blipAngle = _getBlipAngleForIndex(idx);

            return AnimatedBuilder(
              animation: _rotationController,
              builder: (context, child) {
                final double sweepAngle = _rotationController.value * 2 * math.pi;
                final double opacity = _getBlipOpacityByAngle(blipAngle, sweepAngle);

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: centerOffset + offset.dx - 17,
                      top: centerOffset + offset.dy - 17,
                      child: GestureDetector(
                        onTap: () {
                          ref.read(selectedInstrumentProvider.notifier).state = symbol;
                        },
                        child: Container(
                          width: 34,
                          height: 34,
                          child: Stack(
                            children: [
                              // Target Corner lines [ ] (Dynamic Opacity based on sweep!)
                              Opacity(
                                opacity: opacity,
                                child: Stack(
                                  children: [
                                    Positioned(
                                      left: 0, top: 0,
                                      child: Container(width: 5, height: 5, decoration: BoxDecoration(border: Border(left: BorderSide(color: signalColor, width: 1.5), top: BorderSide(color: signalColor, width: 1.5)))),
                                    ),
                                    Positioned(
                                      right: 0, top: 0,
                                      child: Container(width: 5, height: 5, decoration: BoxDecoration(border: Border(right: BorderSide(color: signalColor, width: 1.5), top: BorderSide(color: signalColor, width: 1.5)))),
                                    ),
                                    Positioned(
                                      left: 0, bottom: 0,
                                      child: Container(width: 5, height: 5, decoration: BoxDecoration(border: Border(left: BorderSide(color: signalColor, width: 1.5), bottom: BorderSide(color: signalColor, width: 1.5)))),
                                    ),
                                    Positioned(
                                      right: 0, bottom: 0,
                                      child: Container(width: 5, height: 5, decoration: BoxDecoration(border: Border(right: BorderSide(color: signalColor, width: 1.5), bottom: BorderSide(color: signalColor, width: 1.5)))),
                                    ),
                                  ],
                                ),
                              ),
                              
                              // Inner logo badge (Always 1.0 opacity - fully clean, bright, and legible!)
                              Center(
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                    boxShadow: [
                                      BoxShadow(
                                        color: signalColor.withValues(alpha: opacity), // Dynamic glowing shadow!
                                        blurRadius: 6,
                                        spreadRadius: 0.8,
                                      ),
                                    ],
                                  ),
                                  child: ClipOval(
                                    child: _buildRadarMiniLogo(symbol),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          }),
        ],
      ),
    );
  }
}

class RadarSignalsList extends ConsumerStatefulWidget {
  const RadarSignalsList({super.key});

  @override
  ConsumerState<RadarSignalsList> createState() => _RadarSignalsListState();
}

class _RadarSignalsListState extends ConsumerState<RadarSignalsList> {
  String _dragFilter = 'all'; // 'all', 'up', 'down'
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _setFilter(String filter) {
    if (_dragFilter != filter) {
      setState(() {
        _dragFilter = filter;
      });
      HapticFeedback.mediumImpact();
    }
  }

  Widget _buildFilterBadge() {
    Color badgeColor;
    String text;
    if (_dragFilter == 'up') {
      badgeColor = AppTheme.bullColor;
      text = 'BULLISH';
    } else if (_dragFilter == 'down') {
      badgeColor = AppTheme.bearColor;
      text = 'BEARISH';
    } else {
      badgeColor = AppTheme.primaryCyan.withValues(alpha: 0.7);
      text = 'ALL';
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        if (_dragFilter == 'all') {
          _setFilter('up');
        } else if (_dragFilter == 'up') {
          _setFilter('down');
        } else {
          _setFilter('all');
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: badgeColor.withValues(alpha: 0.4),
            width: 0.8,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: badgeColor,
            fontSize: 7.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final signalsAsync = ref.watch(globalSignalsProvider);
    final List<Map<String, dynamic>> signals = signalsAsync.value ?? [];
    
    final List<Map<String, dynamic>> activeTargets = signals.isNotEmpty
        ? signals
        : [
            {
              'symbol': AppConstants.nifty50,
              'buyerCount': 120,
              'sellerCount': 30,
            },
            {
              'symbol': AppConstants.bankNifty,
              'buyerCount': 40,
              'sellerCount': 150,
            },
            {
              'symbol': 'TCS',
              'buyerCount': 90,
              'sellerCount': 10,
            }
          ];

    final List<Map<String, dynamic>> filteredTargets = activeTargets.where((target) {
      if (_dragFilter == 'all') return true;
      final int buyerCount = target['buyerCount'] ?? 0;
      final int sellerCount = target['sellerCount'] ?? 0;
      final bool isBuy = buyerCount >= sellerCount;
      if (_dragFilter == 'up') return isBuy;
      if (_dragFilter == 'down') return !isBuy;
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // TECH HEADER FOR ACTIVE LIST
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.list_alt_rounded, color: AppTheme.primaryCyan, size: 12),
              const SizedBox(width: 6),
              const Text(
                'LIVE DETECTED SIGNALS',
                style: TextStyle(
                  color: AppTheme.subTextColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              _buildFilterBadge(),
              const SizedBox(width: 8),
              _VerticalDragFilter(
                currentValue: _dragFilter,
                onChanged: _setFilter,
              ),
            ],
          ),
        ),

        // 3. STOCKS LIST
        SizedBox(
          height: 350,
          child: filteredTargets.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'No active signals matching filter',
                      style: TextStyle(color: Colors.white24, fontSize: 10),
                    ),
                  ),
                )
              : ScrollConfiguration(
                  behavior: const _MouseDragScrollBehavior(),
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.zero,
                    itemCount: filteredTargets.length,
                    itemBuilder: (context, index) {
                      final target = filteredTargets[index];
                      final String symbol = target['symbol'] ?? '';
                      final int buyerCount = target['buyerCount'] ?? 0;
                      final int sellerCount = target['sellerCount'] ?? 0;
                      final bool isTrap = target['isTrap'] ?? false;
                      final bool isLiquidation = target['isLiquidation'] ?? false;
                      final bool isBuy = buyerCount >= sellerCount;
                      final Color signalColor = isBuy ? AppTheme.bullColor : AppTheme.bearColor;

                      String signalDetails = 'Imbalance: ${buyerCount}K vs ${sellerCount}K';
                      if (isTrap) signalDetails = 'Institutional Trap detected';
                      if (isLiquidation) signalDetails = 'Big liquidation block detected';

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            ref.read(selectedInstrumentProvider.notifier).state = symbol;
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.03))),
                            ),
                            child: Row(
                              children: [
                                // Stock Mini Logo badge
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                  ),
                                  child: ClipOval(
                                    child: _buildRadarMiniLogo(symbol),
                                  ),
                                ),
                                const SizedBox(width: 10),

                                // Symbol & details text
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        symbol,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 11,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        signalDetails,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white38,
                                          fontSize: 8,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // BUY/SELL Glowing pill card
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: signalColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: signalColor.withValues(alpha: 0.3),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    isBuy ? 'BUY' : 'SELL',
                                    style: TextStyle(
                                      color: signalColor,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 8,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _VerticalDragFilter extends StatefulWidget {
  final String currentValue;
  final ValueChanged<String> onChanged;

  const _VerticalDragFilter({
    required this.currentValue,
    required this.onChanged,
  });

  @override
  State<_VerticalDragFilter> createState() => _VerticalDragFilterState();
}

class _VerticalDragFilterState extends State<_VerticalDragFilter> {
  double _dragY = 12.0; // center/all position is default
  final double _trackHeight = 36.0;
  final double _handleHeight = 12.0;

  @override
  void initState() {
    super.initState();
    _updateDragYFromValue();
  }

  @override
  void didUpdateWidget(covariant _VerticalDragFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentValue != widget.currentValue) {
      _updateDragYFromValue();
    }
  }

  void _updateDragYFromValue() {
    setState(() {
      if (widget.currentValue == 'up') {
        _dragY = 0.0;
      } else if (widget.currentValue == 'down') {
        _dragY = _trackHeight - _handleHeight;
      } else {
        _dragY = (_trackHeight - _handleHeight) / 2;
      }
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final localPosition = renderBox.globalToLocal(details.globalPosition);
    final maxDrag = _trackHeight - _handleHeight;
    setState(() {
      _dragY = localPosition.dy.clamp(0.0, maxDrag);
    });

    final relativePos = _dragY / maxDrag;
    String newValue;
    if (relativePos < 0.3) {
      newValue = 'up';
    } else if (relativePos > 0.7) {
      newValue = 'down';
    } else {
      newValue = 'all';
    }

    if (newValue != widget.currentValue) {
      widget.onChanged(newValue);
    }
  }

  void _onDragEnd(DragEndDetails details) {
    _updateDragYFromValue();
  }

  @override
  Widget build(BuildContext context) {
    final Color handleColor = widget.currentValue == 'up'
        ? AppTheme.bullColor
        : (widget.currentValue == 'down' ? AppTheme.bearColor : AppTheme.primaryCyan);

    return GestureDetector(
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      onTapDown: (details) {
        final RenderBox renderBox = context.findRenderObject() as RenderBox;
        final localPosition = renderBox.globalToLocal(details.globalPosition);
        final relativePos = localPosition.dy / _trackHeight;
        String newValue;
        if (relativePos < 0.35) {
          newValue = 'up';
        } else if (relativePos > 0.65) {
          newValue = 'down';
        } else {
          newValue = 'all';
        }
        widget.onChanged(newValue);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: Container(
          width: 14,
          height: _trackHeight,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Center track line
              Center(
                child: Container(
                  width: 2,
                  height: _trackHeight - 6,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              // Notches
              Positioned(
                top: 4,
                left: 4,
                child: Container(width: 4, height: 1.5, color: AppTheme.bullColor.withValues(alpha: 0.5)),
              ),
              Positioned(
                top: _trackHeight / 2 - 0.75,
                left: 4,
                child: Container(width: 4, height: 1.5, color: AppTheme.primaryCyan.withValues(alpha: 0.5)),
              ),
              Positioned(
                bottom: 4,
                left: 4,
                child: Container(width: 4, height: 1.5, color: AppTheme.bearColor.withValues(alpha: 0.5)),
              ),
              // Glowing Handle
              Positioned(
                top: _dragY,
                left: 1,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: 10,
                  height: _handleHeight,
                  decoration: BoxDecoration(
                    color: handleColor,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: handleColor.withValues(alpha: 0.6),
                        blurRadius: 4,
                        spreadRadius: 0.5,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MouseDragScrollBehavior extends MaterialScrollBehavior {
  const _MouseDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

class NetworkSpeedMeter extends StatefulWidget {
  const NetworkSpeedMeter({super.key});

  @override
  State<NetworkSpeedMeter> createState() => _NetworkSpeedMeterState();
}

class _NetworkSpeedMeterState extends State<NetworkSpeedMeter> {
  late Timer _timer;
  double _dlSpeed = 8.5; // MB/s
  int _latency = 28; // ms
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) return;
      setState(() {
        _dlSpeed = 2.0 + _random.nextDouble() * 12.0;
        _latency = 12 + _random.nextInt(32);
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color latencyColor = const Color(0xFF00FF88); // green
    if (_latency > 60) {
      latencyColor = Colors.amberAccent;
    } else if (_latency > 150) {
      latencyColor = Colors.redAccent;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1),
        boxShadow: [
          BoxShadow(
            color: latencyColor.withValues(alpha: 0.12),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Glowing status indicator dot
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: latencyColor,
              boxShadow: [
                BoxShadow(color: latencyColor.withValues(alpha: 0.8), blurRadius: 6, spreadRadius: 2),
              ],
            ),
          ),
          const SizedBox(width: 7),

          // Latency display
          Text(
            '${_latency}ms',
            style: TextStyle(
              color: latencyColor,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 8),

          // Divider
          Container(width: 1, height: 12, color: Colors.white24),
          const SizedBox(width: 8),

          // Download Speed icon + value
          const Icon(Icons.arrow_downward_rounded, color: Color(0xFF00FF88), size: 12),
          const SizedBox(width: 3),
          Text(
            '${_dlSpeed.toStringAsFixed(1)} MB/s',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class SmartAlert {
  final String id;
  final String type; // 'price_cross' | 'imbalance' | 'signal'
  final double? targetPrice;
  final int? minImbalancePct;
  final String? signalType;
  final String soundName;
  final String description;
  bool isActive;

  SmartAlert({
    required this.id,
    required this.type,
    this.targetPrice,
    this.minImbalancePct,
    this.signalType,
    this.soundName = 'alert',
    required this.description,
    this.isActive = true,
  });
}

class PreMarketBiasDashboard extends StatefulWidget {
  const PreMarketBiasDashboard({super.key});

  @override
  State<PreMarketBiasDashboard> createState() => _PreMarketBiasDashboardState();
}

class _PreMarketBiasDashboardState extends State<PreMarketBiasDashboard> {
  bool _isExpanded = false;
  
  double _giftNifty = 24185.50;
  double _giftNiftyChange = 112.50;
  double _giftNiftyPct = 0.47;
  String _expectedOpen = "GAP UP (+90 to +110 points)";
  String _fiiFlow = "+₹1,482.50 Cr";
  String _diiFlow = "-₹328.10 Cr";
  Map<String, String> _globalFutures = {};
  String _lastUpdatedTime = "";

  @override
  void initState() {
    super.initState();
    _refreshPreMarketBias();
  }

  void _refreshPreMarketBias() {
    final now = DateTime.now();
    final seed = now.year * 10000 + now.month * 100 + now.day;
    final rng = math.Random(seed);

    final bool isBullishDay = (seed % 3) != 0;

    if (isBullishDay) {
      _giftNiftyChange = 60.0 + (rng.nextDouble() * 95.0);
      _giftNiftyPct = (_giftNiftyChange / 24100.0) * 100;
      _giftNifty = 24185.50 + _giftNiftyChange;
      final int minPts = _giftNiftyChange.toInt() - 15;
      final int maxPts = _giftNiftyChange.toInt() + 15;
      _expectedOpen = "GAP UP (+$minPts to +$maxPts points)";
      _fiiFlow = "+₹${(1000 + rng.nextDouble() * 1500).toStringAsFixed(2)} Cr";
      _diiFlow = "-₹${(100 + rng.nextDouble() * 500).toStringAsFixed(2)} Cr";
      _globalFutures = {
        'DOW FUT': '+${(50 + rng.nextInt(120))} (0.${rng.nextInt(45)}%)',
        'NASDAQ FUT': '+${(40 + rng.nextInt(90))} (0.${rng.nextInt(60)}%)',
        'DAX': '+${(10 + rng.nextInt(40))} (0.${rng.nextInt(25)}%)',
        'NIKKEI': '+${(180 + rng.nextInt(250))} (0.${rng.nextInt(90)}%)',
      };
    } else {
      _giftNiftyChange = -(45.0 + (rng.nextDouble() * 80.0));
      _giftNiftyPct = (_giftNiftyChange / 24100.0) * 100;
      _giftNifty = 24185.50 + _giftNiftyChange;
      final int minPts = _giftNiftyChange.toInt() - 15;
      final int maxPts = _giftNiftyChange.toInt() + 15;
      _expectedOpen = "GAP DOWN ($minPts to $maxPts points)";
      _fiiFlow = "-₹${(800 + rng.nextDouble() * 1200).toStringAsFixed(2)} Cr";
      _diiFlow = "+₹${(400 + rng.nextDouble() * 900).toStringAsFixed(2)} Cr";
      _globalFutures = {
        'DOW FUT': '-${(40 + rng.nextInt(90))} (-0.${rng.nextInt(35)}%)',
        'NASDAQ FUT': '-${(30 + rng.nextInt(80))} (-0.${rng.nextInt(45)}%)',
        'DAX': '-${(15 + rng.nextInt(35))} (-0.${rng.nextInt(20)}%)',
        'NIKKEI': '-${(120 + rng.nextInt(200))} (-0.${rng.nextInt(70)}%)',
      };
    }

    _lastUpdatedTime = intl.DateFormat('dd-MM-yyyy • 08:45 AM').format(now);

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header (Clickable for Expand/Collapse)
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.analytics_outlined, color: AppTheme.goldColor, size: 16),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'PRE-MARKET BIAS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      if (_lastUpdatedTime.isNotEmpty)
                        Text(
                          'UPDATED: $_lastUpdatedTime',
                          style: const TextStyle(
                            color: AppTheme.primaryCyan,
                            fontSize: 7.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: AppTheme.primaryCyan, size: 16),
                    onPressed: _refreshPreMarketBias,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Refresh Pre-Market Data',
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: Colors.white38,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
          
          if (_isExpanded) ...[
            const Divider(color: Colors.white10, height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Gift Nifty
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('GIFT NIFTY', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          Text(
                            _giftNifty.toStringAsFixed(2),
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, fontFamily: 'monospace'),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '+${_giftNiftyChange.toStringAsFixed(2)} (+${_giftNiftyPct.toStringAsFixed(2)}%)',
                            style: const TextStyle(color: Color(0xFF00FF88), fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  
                  // Expected Open
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('EXPECTED OPEN', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00FF88).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF00FF88).withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          _expectedOpen,
                          style: const TextStyle(color: Color(0xFF00FF88), fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: 0.3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 8),
                  
                  // FII / DII Flow
                  const Text('FII / DII NET FLOW (PREV DAY)', style: TextStyle(color: Colors.white38, fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildFlowRow('FII Buy', _fiiFlow, const Color(0xFF00FF88)),
                      _buildFlowRow('DII Sell', _diiFlow, AppTheme.bearColor),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 8),
                  
                  // Global Futures
                  const Text('GLOBAL FUTURES & INDICES', style: TextStyle(color: Colors.white38, fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 3.2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: _globalFutures.entries.map((e) {
                      final isPositive = e.value.startsWith('+');
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(e.key, style: const TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(
                              e.value,
                              style: TextStyle(
                                color: isPositive ? const Color(0xFF00FF88) : AppTheme.bearColor,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFlowRow(String label, String value, Color color) {
    return Row(
      children: [
        Text('$label: ', style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
        Text(
          value,
          style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w900, fontFamily: 'monospace'),
        ),
      ],
    );
  }
}

class AllowMultipleScaleGestureRecognizer extends ScaleGestureRecognizer {
  @override
  void rejectGesture(int pointer) {
    acceptGesture(pointer);
  }
}

// ─── PRO-GRADE ANIMATED APP UPDATE PROMPT DIALOG ───
class AppUpdatePromptDialog extends StatefulWidget {
  final String latestVersion;
  final String updateUrl;
  final String changelog;
  final bool forceUpdate;

  const AppUpdatePromptDialog({
    super.key,
    required this.latestVersion,
    required this.updateUrl,
    required this.changelog,
    required this.forceUpdate,
  });

  @override
  State<AppUpdatePromptDialog> createState() => _AppUpdatePromptDialogState();
}

class _AppUpdatePromptDialogState extends State<AppUpdatePromptDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );

    _glowAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutSine,
      ),
    );

    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = widget.forceUpdate ? AppTheme.bearColor : AppTheme.primaryCyan;

    return PopScope(
      canPop: !widget.forceUpdate,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF0E1824),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: primaryColor.withValues(alpha: 0.6),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.2),
                    blurRadius: 40,
                    spreadRadius: 6,
                  ),
                  BoxShadow(
                    color: AppTheme.goldColor.withValues(alpha: 0.1),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _glowAnimation.value,
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: primaryColor.withValues(alpha: 0.12),
                            border: Border.all(color: primaryColor.withValues(alpha: 0.5), width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: primaryColor.withValues(alpha: 0.4),
                                blurRadius: 20,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: Icon(
                            widget.forceUpdate ? Icons.security_update_warning_rounded : Icons.system_update_rounded,
                            color: primaryColor,
                            size: 36,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'NEW UPDATE AVAILABLE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      fontFamily: 'monospace',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.goldColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.goldColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      'v${widget.latestVersion}',
                      style: const TextStyle(
                        color: AppTheme.goldColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  if (widget.forceUpdate) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.bearColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.bearColor.withValues(alpha: 0.3)),
                      ),
                      child: const Text(
                        '⚠️ MANDATORY UPDATE',
                        style: TextStyle(
                          color: AppTheme.bearColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                  if (widget.changelog.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "WHAT'S NEW",
                            style: TextStyle(
                              color: AppTheme.dimTextColor,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.changelog,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isDownloading
                          ? null
                          : () async {
                              setState(() => _isDownloading = true);
                              HapticFeedback.heavyImpact();
                              String targetUrl = widget.updateUrl.trim();
                              if (targetUrl.isEmpty || targetUrl.contains('firebasestorage.googleapis.com')) {
                                targetUrl = 'https://orderflowterminal.web.app/app-release.apk';
                              }
                              final uri = Uri.tryParse(targetUrl);
                              if (uri != null) {
                                try {
                                  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
                                  if (!launched) {
                                    await launchUrl(uri, mode: LaunchMode.platformDefault);
                                  }
                                } catch (e) {
                                  debugPrint('[LAUNCH_UPDATE_URL_ERROR] $e');
                                }
                              }
                              if (mounted) {
                                setState(() => _isDownloading = false);
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: AppTheme.bgColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 8,
                      ),
                      icon: _isDownloading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.bgColor),
                            )
                          : const Icon(Icons.download_rounded),
                      label: Text(
                        _isDownloading ? 'DOWNLOADING...' : 'UPDATE NOW',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  if (!widget.forceUpdate) ...[
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'REMIND ME LATER',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
