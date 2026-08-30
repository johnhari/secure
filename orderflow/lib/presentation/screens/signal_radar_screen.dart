import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/nifty_stocks.dart';
import '../../core/constants/stock_logos.dart';
import '../../core/utils/open_drive_helper.dart';
import '../providers/providers.dart';
import '../providers/instrument_provider.dart';
import '../providers/auth_provider.dart';

class SignalRadarScreen extends ConsumerStatefulWidget {
  const SignalRadarScreen({super.key});

  @override
  ConsumerState<SignalRadarScreen> createState() => _SignalRadarScreenState();
}

class _SignalRadarScreenState extends ConsumerState<SignalRadarScreen> with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;
  final math.Random _random = math.Random();
  final List<Offset> _blips = [];
  String _dragFilter = 'all'; // 'all', 'up', 'down'

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
    } else if (_dragFilter == 'od') {
      badgeColor = AppTheme.goldColor;
      text = '⚡ OD STOCKS (OPEN=HIGH/LOW)';
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
        } else if (_dragFilter == 'down') {
          _setFilter('od');
        } else {
          _setFilter('all');
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: badgeColor.withValues(alpha: 0.6),
            width: 1.0,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: badgeColor,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
  
  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();

    // Generate static random positions for decorative radar blips
    for (int i = 0; i < 8; i++) {
      final angle = _random.nextDouble() * 2 * math.pi;
      final radius = 30 + _random.nextDouble() * 110;
      _blips.add(Offset(
        math.cos(angle) * radius,
        math.sin(angle) * radius,
      ));
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  void _navigateToStock(String symbol) {
    ref.read(selectedInstrumentProvider.notifier).state = symbol;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (previous, next) {
      if (next.status == AuthStatus.unauthenticated) {
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
        }
      }
    });

    final signalsAsync = ref.watch(globalSignalsProvider);
    final List<Map<String, dynamic>> signals = signalsAsync.value ?? [];
    final double width = MediaQuery.of(context).size.width;
    final bool isDesktop = width > 900;

    return Scaffold(
      backgroundColor: const Color(0xFF06090D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1520),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.radar_rounded, color: AppTheme.goldColor, size: 22),
            const SizedBox(width: 10),
            const Text(
              'ORDERFLOW SIGNAL RADAR',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primaryCyan.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppTheme.primaryCyan.withValues(alpha: 0.4), width: 0.8),
              ),
              child: const Text(
                'LIVE TELEMETRY',
                style: TextStyle(
                  color: AppTheme.primaryCyan,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // Futuristic Background Ambient Glows
          Positioned(
            top: -100,
            left: -100,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.cyan.withValues(alpha: 0.03),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            right: -150,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 90, sigmaY: 90),
              child: Container(
                width: 350,
                height: 350,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.purple.withValues(alpha: 0.03),
                ),
              ),
            ),
          ),

          // Main Responsive Content
          SafeArea(
            child: isDesktop
                ? Row(
                    children: [
                      // Left side: Radar animation pane
                      Expanded(
                        flex: 12,
                        child: _buildRadarPane(signals),
                      ),
                      // Divider line
                      Container(
                        width: 1.5,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      // Right side: Signals feed
                      Expanded(
                        flex: 13,
                        child: _buildSignalsFeed(signalsAsync),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      // Smaller radar block at top for mobile/portrait screen sizing
                      Container(
                        height: 240,
                        color: const Color(0xFF090D14),
                        child: _buildRadarPane(signals),
                      ),
                      Container(
                        height: 1.5,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      Expanded(
                        child: _buildSignalsFeed(signalsAsync),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // Deterministic coordinate based on symbol hash
  Offset _getSymbolOffset(String symbol, double radarRadius) {
    final int hash = symbol.hashCode;
    // Map hash to angle in [0, 2*pi]
    final double angle = (hash % 360) * math.pi / 180;
    // Map hash to distance from center in [40, radarRadius - 20]
    final double radius = 40 + (hash.abs() % (radarRadius.toInt() - 60));
    return Offset(
      math.cos(angle) * radius,
      math.sin(angle) * radius,
    );
  }

  double _getBlipOpacity(String symbol, double sweepAngle) {
    final int hash = symbol.hashCode;
    final double blipAngle = (hash % 360) * math.pi / 180; // 0 to 2*pi
    
    // Calculate angular difference
    double diff = (sweepAngle - blipAngle) % (2 * math.pi);
    
    if (diff < 1.0) {
      return 1.0 - diff; // fully lit at sweep line, fades out over 1.0 radian tail
    }
    return 0.15; // default dim state
  }

  bool _shouldShowPopup(String symbol, double sweepAngle) {
    final int hash = symbol.hashCode;
    final double blipAngle = (hash % 360) * math.pi / 180;
    double diff = (sweepAngle - blipAngle) % (2 * math.pi);
    return diff < 0.6; // show popup while the sweep line is within 0.6 radians past the blip
  }

  Widget _buildMiniLogo(String symbol) {
    final cleanSymbol = StockLogos.cleanSymbol(symbol);
    if (StockLogos.localAssets.containsKey(cleanSymbol)) {
      return Image.asset(
        StockLogos.localAssets[cleanSymbol]!,
        fit: BoxFit.cover,
        width: 16,
        height: 16,
        errorBuilder: (context, error, stackTrace) => _buildDefaultMiniLogo(),
      );
    }
    return _MiniLogoWithFallback(
      primaryUrl: StockLogos.getLogoUrl(cleanSymbol),
      fallbackUrl: StockLogos.getFallbackLogoUrl(cleanSymbol),
      size: 16,
      defaultWidget: _buildDefaultMiniLogo(),
    );
  }

  Widget _buildDefaultMiniLogo() {
    return Image.asset(
      'assets/images/logo_bigshot.jpg',
      fit: BoxFit.cover,
      width: 16,
      height: 16,
    );
  }

  // ── Radar Sweeper Pane ───────────────────────────────────────────
  Widget _buildRadarPane(List<Map<String, dynamic>> signals) {
    final authState = ref.watch(authProvider);
    final isIndexOnly = authState.user?.isIndexOnly ?? false;
    final List<Map<String, dynamic>> visibleSignals = isIndexOnly
        ? signals.where((s) => NiftyStocks.isIndexOnlyAllowed(s['symbol'] as String? ?? '')).toList()
        : signals;

    final List<Map<String, dynamic>> activeTargets = visibleSignals.isNotEmpty
        ? visibleSignals
        : [
            {
              'symbol': AppConstants.nifty50,
              'buyerCount': 120,
              'sellerCount': 30,
              'isTrap': false,
            },
            {
              'symbol': AppConstants.bankNifty,
              'buyerCount': 40,
              'sellerCount': 150,
              'isTrap': true,
            },
            {
              'symbol': 'TCS',
              'buyerCount': 90,
              'sellerCount': 10,
              'isTrap': false,
            }
          ];

    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 16),
            Stack(
              alignment: Alignment.center,
              children: [
                // 1. Decorative Glowing outer radar ring (Green theme matching user's image!)
                Container(
                  width: 320,
                  height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF00FF66).withValues(alpha: 0.15),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00FF66).withValues(alpha: 0.03),
                        blurRadius: 25,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF00FF66).withValues(alpha: 0.08),
                      width: 1,
                    ),
                  ),
                ),
                Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF00FF66).withValues(alpha: 0.06),
                      width: 1,
                    ),
                  ),
                ),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF00FF66).withValues(alpha: 0.04),
                      width: 1,
                    ),
                  ),
                ),
                
                // Crosshairs
                Container(
                  width: 320,
                  height: 1,
                  color: const Color(0xFF00FF66).withValues(alpha: 0.05),
                ),
                Container(
                  width: 1,
                  height: 320,
                  color: const Color(0xFF00FF66).withValues(alpha: 0.05),
                ),

                // 2. Rotating Radar Scanner sweep image (Green sweep gradient fallback)
                RotationTransition(
                  turns: _rotationController,
                  child: Container(
                    width: 320,
                    height: 320,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: [
                          const Color(0xFF00FF66).withValues(alpha: 0.35),
                          const Color(0xFF00FF66).withValues(alpha: 0.08),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.35, 1.0],
                      ),
                    ),
                  ),
                ),

                // 3. Dynamic target blips and details popups
                ...activeTargets.map((target) {
                  final String symbol = target['symbol'] ?? '';
                  final int buyerCount = target['buyerCount'] ?? 0;
                  final int sellerCount = target['sellerCount'] ?? 0;
                  final bool isBuy = buyerCount >= sellerCount;
                  final Color signalColor = isBuy ? AppTheme.bullColor : AppTheme.bearColor;
                  
                  // Get coordinate mapping (max radius is 140)
                  final Offset offset = _getSymbolOffset(symbol, 140);

                  return AnimatedBuilder(
                    animation: _rotationController,
                    builder: (context, child) {
                      final double sweepAngle = _rotationController.value * 2 * math.pi;
                      final double opacity = _getBlipOpacity(symbol, sweepAngle);
                      final bool showPopup = _shouldShowPopup(symbol, sweepAngle);
                      
                      // Calculate fade factor for popup
                      final int hash = symbol.hashCode;
                      final double blipAngle = (hash % 360) * math.pi / 180;
                      double diff = (sweepAngle - blipAngle) % (2 * math.pi);
                      final double popupOpacity = (1.0 - (diff / 0.6)).clamp(0.0, 1.0);

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                           // The target blip logo badge
                           Positioned(
                            left: 160 + offset.dx - 12,
                            top: 160 + offset.dy - 12,
                            child: Opacity(
                              opacity: opacity,
                              child: GestureDetector(
                                onTap: () => _navigateToStock(symbol),
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                    border: Border.all(
                                      color: signalColor,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(color: signalColor, blurRadius: 8, spreadRadius: 2),
                                    ],
                                  ),
                                  child: ClipOval(
                                    child: _buildMiniLogo(symbol),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Pop-up Stock Details label (fades in as sweeper hits the target)
                          if (showPopup)
                            Positioned(
                              left: 160 + offset.dx + 12,
                              top: 160 + offset.dy - 20,
                              child: Opacity(
                                opacity: popupOpacity,
                                child: IgnorePointer(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const ui.Color(0xEE0B0E14),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: signalColor.withValues(alpha: 0.6),
                                        width: 1.2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: signalColor.withValues(alpha: 0.25),
                                          blurRadius: 8,
                                          spreadRadius: 0.5,
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Mini Stock Logo
                                        Container(
                                          width: 16,
                                          height: 16,
                                          decoration: const BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                          alignment: Alignment.center,
                                          child: ClipOval(
                                            child: _buildMiniLogo(symbol),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              symbol == AppConstants.nifty50
                                                  ? 'NIFTY'
                                                  : (symbol == AppConstants.bankNifty ? 'BANK' : symbol),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 1),
                                            Text(
                                              isBuy ? 'BUY DETECTED' : 'SELL DETECTED',
                                              style: TextStyle(
                                                color: signalColor,
                                                fontSize: 7,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  );
                }),

                // Center indicator dot
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.white, blurRadius: 6),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Scanner telemetry tags
            const Text(
              'FREQUENCY: 9.42 GHz  |  SYSTEM STATUS: ONLINE',
              style: TextStyle(
                color: Color(0xFF00FF66),
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: Color(0xFF00FF66),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'SCANNING INSTITUTIONAL ORDERFLOW DATA...',
                  style: TextStyle(
                    color: Color(0xFF00FF66),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSignalsFeed(AsyncValue<List<Map<String, dynamic>>> signalsAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 24, right: 24, top: 20, bottom: 8),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LIVE TELEMETRY FEED',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Real-time institutional volume spikes, traps, and imbalances',
                      style: TextStyle(
                        color: Colors.white30,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildFilterBadge(),
              const SizedBox(width: 10),
              _VerticalDragFilter(
                currentValue: _dragFilter,
                onChanged: _setFilter,
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        Expanded(
          child: signalsAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryCyan),
            ),
            error: (err, stack) => Center(
              child: Text(
                'Telemetry stream failure: $err',
                style: const TextStyle(color: AppTheme.bearColor),
              ),
            ),
            data: (signals) {
              final authState = ref.watch(authProvider);
              final isIndexOnly = authState.user?.isIndexOnly ?? false;
              final visibleSignals = isIndexOnly
                  ? signals.where((s) => NiftyStocks.isIndexOnlyAllowed(s['symbol'] as String? ?? '')).toList()
                  : signals;

              final filteredSignals = visibleSignals.where((signal) {
                final int buyerCount = signal['buyerCount'] ?? 0;
                final int sellerCount = signal['sellerCount'] ?? 0;
                final bool isBuy = buyerCount >= sellerCount;
                final double open = (signal['open'] as num?)?.toDouble() ?? 0.0;
                final double high = (signal['high'] as num?)?.toDouble() ?? 0.0;
                final double low = (signal['low'] as num?)?.toDouble() ?? 0.0;
                final double close = (signal['price'] as num?)?.toDouble() ?? 0.0;
                
                final bool isRetested = signal['isRetested'] == true || signal['retested'] == true;
                final bool isOD = !isRetested && (signal['isOD'] == true ||
                    (open > 0 && OpenDriveHelper.isOpenDriveValid(
                      open: open,
                      high: high,
                      low: low,
                      close: close,
                      isRetestedBefore1015: isRetested,
                    )) ||
                    (signal['isBigSignal'] == true && (buyerCount >= 50000 || sellerCount >= 50000)));

                if (_dragFilter == 'up') return isBuy;
                if (_dragFilter == 'down') return !isBuy;
                if (_dragFilter == 'od') return isOD;
                return true;
              }).toList();

              if (filteredSignals.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.sensors_off_rounded, color: Colors.white24, size: 40),
                      const SizedBox(height: 12),
                      Text(
                        _dragFilter == 'all'
                            ? 'NO ACTIVE TELEMETRY SIGNALS'
                            : 'NO ${_dragFilter.toUpperCase()} SIGNALS FOUND',
                        style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Waiting for admin signal injection...',
                        style: TextStyle(color: Colors.white24, fontSize: 9),
                      ),
                    ],
                  ),
                );
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragEnd: (details) {
                  if (details.primaryVelocity != null) {
                    if (details.primaryVelocity! < -150) {
                      _setFilter('up');
                    } else if (details.primaryVelocity! > 150) {
                      _setFilter('down');
                    }
                  }
                },
                onDoubleTap: () {
                  _setFilter('all');
                },
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  itemCount: filteredSignals.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final signal = filteredSignals[index];
                    final String symbol = signal['symbol'] ?? '';
                    final String name = AppConstants.instrumentNames[symbol] ?? symbol;
                    final int candleTime = signal['candleTime'] ?? 0;
                    final int buyerCount = signal['buyerCount'] ?? 0;
                    final int sellerCount = signal['sellerCount'] ?? 0;
                    final bool isTrap = signal['isTrap'] ?? false;
                    final bool isLiquidation = signal['isLiquidation'] ?? false;
                    final bool isInstitutional = signal['isInstitutional'] ?? false;
                    final bool isBigSignal = signal['isBigSignal'] ?? false;
                    final String customTag = signal['customTag'] ?? '';

                    final bool isBuy = buyerCount >= sellerCount;
                    final Color directionColor = isBuy ? AppTheme.bullColor : AppTheme.bearColor;
                    final String directionText = isBuy ? 'BUY' : 'SELL';
                    final IconData directionIcon = isBuy ? Icons.trending_up_rounded : Icons.trending_down_rounded;

                    final dt = DateTime.fromMillisecondsSinceEpoch(candleTime);
                    final timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _navigateToStock(symbol),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F1520).withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: directionColor.withValues(alpha: 0.15),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
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
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          timeStr,
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.3),
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      name,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.45),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
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
                                      else if (isInstitutional || isBigSignal)
                                        _buildSignalBadge('INSTITUTIONAL', AppTheme.goldColor)
                                      else if (customTag.isNotEmpty)
                                        _buildSignalBadge(customTag.toUpperCase(), AppTheme.primaryCyan),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: directionColor.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          directionText,
                                          style: TextStyle(
                                            color: directionColor,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Vol: ${(isBuy ? buyerCount : sellerCount).toString()}',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.6),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSignalBadge(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MiniLogoWithFallback extends StatefulWidget {
  final String primaryUrl;
  final String fallbackUrl;
  final double size;
  final Widget defaultWidget;

  const _MiniLogoWithFallback({
    required this.primaryUrl,
    required this.fallbackUrl,
    required this.size,
    required this.defaultWidget,
  });

  @override
  State<_MiniLogoWithFallback> createState() => _MiniLogoWithFallbackState();
}

class _MiniLogoWithFallbackState extends State<_MiniLogoWithFallback> {
  bool _primaryFailed = false;
  bool _fallbackFailed = false;

  @override
  void didUpdateWidget(_MiniLogoWithFallback oldWidget) {
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.size * 0.5),
      child: Image.network(
        url,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
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
