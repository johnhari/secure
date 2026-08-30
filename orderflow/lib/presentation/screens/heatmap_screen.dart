import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:ui';
import 'dart:async';
import '../../core/services/market_time_service.dart';
import '../../core/theme/app_theme.dart';
import '../providers/instrument_provider.dart';
import '../providers/heatmap_provider.dart';
import '../../core/constants/nifty_stocks.dart';
import '../../core/constants/stock_logos.dart';
import '../../core/utils/open_drive_helper.dart';
import '../providers/auth_provider.dart';

class HeatmapScreen extends ConsumerStatefulWidget {
  const HeatmapScreen({super.key});

  @override
  ConsumerState<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends ConsumerState<HeatmapScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _sortBy = 'gainers'; // 'gainers' | 'losers' | 'alphabetical'
  bool _isRefreshing = false;
  bool _isBackgroundUpdating = false;
  Timer? _liveUpdateTimer;

  @override
  void initState() {
    super.initState();
    _triggerOnDemandFetch();
    
    // Set up live update timer every 15 seconds when market is open
    _liveUpdateTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (MarketTimeService.isMarketOpen()) {
        _triggerSilentFetch();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _liveUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _triggerOnDemandFetch() async {
    setState(() => _isRefreshing = true);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('getHeatmapData');
      await callable.call();
      debugPrint('[HeatmapScreen] Live fetch complete.');
    } catch (e) {
      debugPrint('[HeatmapScreen] Failed to trigger live fetch: $e');
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _triggerSilentFetch() async {
    if (_isBackgroundUpdating || _isRefreshing) return;
    _isBackgroundUpdating = true;
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('getHeatmapData');
      await callable.call();
      debugPrint('[HeatmapScreen] Silent live fetch complete.');
    } catch (e) {
      debugPrint('[HeatmapScreen] Failed to trigger silent live fetch: $e');
    } finally {
      _isBackgroundUpdating = false;
    }
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

    final heatmapState = ref.watch(heatmapStreamProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      appBar: AppBar(
        title: const Text(
          'NIFTY 50 HEATMAP',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryCyan,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _isRefreshing ? null : _triggerOnDemandFetch,
          ),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: heatmapState.when(
        data: (data) => _buildContent(data),
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryCyan),
        ),
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppTheme.bearColor, size: 48),
              const SizedBox(height: 16),
              Text(
                'Failed to load heatmap: $err',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _triggerOnDemandFetch,
                child: const Text('Retry'),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(Map<String, Map<String, dynamic>> heatmapData) {
    // 1. Map data keys to list of stock models
    final List<Map<String, dynamic>> stocks = [];
    heatmapData.forEach((symbol, rawData) {
      stocks.add({
        'symbol': symbol,
        'name': rawData['name'] ?? NiftyStocks.stocks[symbol] ?? symbol,
        'price': (rawData['price'] as num?)?.toDouble() ?? 0.0,
        'changePercent': (rawData['changePercent'] as num?)?.toDouble() ?? 0.0,
        'volume': rawData['volume'] as int? ?? 0,
      });
    });

    // If data is empty on RTDB, fallback list of symbols from constants with 0% changes
    if (stocks.isEmpty) {
      NiftyStocks.stocks.forEach((symbol, name) {
        stocks.add({
          'symbol': symbol,
          'name': name,
          'price': 0.0,
          'changePercent': 0.0,
          'volume': 0,
        });
      });
    }

    // 2. Filter list by search query & OD filter
    final filteredStocks = stocks.where((stock) {
      final sym = (stock['symbol'] as String).toLowerCase();
      final name = (stock['name'] as String).toLowerCase();
      final query = _searchQuery.toLowerCase();
      final matchesQuery = sym.contains(query) || name.contains(query);
      if (!matchesQuery) return false;

      if (_sortBy == 'od') {
        final double open = (stock['open'] as num?)?.toDouble() ?? 0.0;
        final double high = (stock['high'] as num?)?.toDouble() ?? 0.0;
        final double low = (stock['low'] as num?)?.toDouble() ?? 0.0;
        final double close = (stock['price'] as num?)?.toDouble() ?? (stock['close'] as num?)?.toDouble() ?? 0.0;
        final bool isRetested = stock['isRetested'] == true || stock['retested'] == true;

        if (isRetested) return false;

        if (open > 0) {
          return OpenDriveHelper.isOpenDriveValid(
            open: open,
            high: high,
            low: low,
            close: close,
            isRetestedBefore1015: isRetested,
          );
        }
        return false;
      }
      return true;
    }).toList();

    // 3. Sort list
    if (_sortBy == 'gainers') {
      filteredStocks.sort((a, b) => (b['changePercent'] as double).compareTo(a['changePercent'] as double));
    } else if (_sortBy == 'losers') {
      filteredStocks.sort((a, b) => (a['changePercent'] as double).compareTo(b['changePercent'] as double));
    } else if (_sortBy == 'alphabetical') {
      filteredStocks.sort((a, b) => (a['symbol'] as String).compareTo(b['symbol'] as String));
    }

    return Column(
      children: [
        // Filter Controls
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            children: [
              // Search Bar
              TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search stock symbol or name...',
                  hintStyle: const TextStyle(color: AppTheme.dimTextColor),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primaryCyan),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: Colors.white60),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.primaryCyan, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Sorting & OD Filter Options Bar
              Row(
                children: [
                  const Text(
                    'FILTER:',
                    style: TextStyle(
                      color: AppTheme.subTextColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildSortChip('gainers', '📈 GAINERS'),
                          const SizedBox(width: 8),
                          _buildSortChip('losers', '📉 LOSERS'),
                          const SizedBox(width: 8),
                          _buildSortChip('od', '⚡ OD STOCKS (OPEN=HIGH/LOW)'),
                          const SizedBox(width: 8),
                          _buildSortChip('alphabetical', '🔤 A-Z'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Grid View of Tiles
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 130,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.9,
            ),
            itemCount: filteredStocks.length,
            itemBuilder: (context, index) {
              final stock = filteredStocks[index];
              return _buildStockTile(stock);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSortChip(String value, String label) {
    final isSelected = _sortBy == value;
    return GestureDetector(
      onTap: () => setState(() => _sortBy = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryCyan.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryCyan : Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.subTextColor,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildStockTile(Map<String, dynamic> stock) {
    final String symbol = stock['symbol'];
    final String name = stock['name'];
    final double price = stock['price'];
    final double changePercent = stock['changePercent'];

    final bool isPositive = changePercent >= 0.0;
    
    // Scale intensity of color based on change (up to 3%)
    final double absVal = changePercent.abs();
    final double colorScale = (absVal / 3.0).clamp(0.15, 0.9);

    final Color tileColor = isPositive
        ? AppTheme.bullColor.withValues(alpha: colorScale)
        : AppTheme.bearColor.withValues(alpha: colorScale);

    // Neon shadow for high volatility changes
    BoxDecoration decoration;
    if (absVal >= 2.5) {
      decoration = BoxDecoration(
        color: tileColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPositive
              ? AppTheme.bullColor.withValues(alpha: 0.8)
              : AppTheme.bearColor.withValues(alpha: 0.8),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isPositive ? AppTheme.bullColor : AppTheme.bearColor).withValues(alpha: 0.35),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      );
    } else {
      decoration = BoxDecoration(
        color: tileColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        ref.read(selectedInstrumentProvider.notifier).state = symbol;
        Navigator.pop(context);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: decoration,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildInstrumentLogo(symbol, size: 18),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          symbol,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 8,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    price > 0 ? '₹${price.toStringAsFixed(2)}' : '—',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isPositive ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                      Text(
                        '${isPositive ? '+' : ''}${changePercent.toStringAsFixed(2)}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
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
    );
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
          border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size / 2),
          child: Image.asset(
            StockLogos.localAssets[cleanSymbol]!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _buildFallbackGradientLogo(symbol, size),
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
            child: Image.network(
              logoUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Image.network(
                  fallbackUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => _buildFallbackGradientLogo(symbol, size),
                );
              },
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
}
