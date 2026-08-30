import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/news_item.dart';
import '../providers/news_provider.dart';
import '../providers/instrument_provider.dart';
import '../providers/candle_provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/stock_logos.dart';
import '../providers/auth_provider.dart';

class NewsScreen extends ConsumerStatefulWidget {
  const NewsScreen({super.key});

  @override
  ConsumerState<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends ConsumerState<NewsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _aiRequested = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openLink(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  String _formatTime(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d').format(date);
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

    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildMarketPulseTab(),
                  _buildWorldEconomyTab(),
                  _buildAiSentimentTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final instrument = ref.watch(selectedInstrumentProvider);
    final candleState = ref.watch(candleStreamProvider);
    final latestCandle = candleState.candles.isNotEmpty ? candleState.candles.last : null;
    final displayPrice = latestCandle != null ? latestCandle.close : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1420).withValues(alpha: 0.60), // Translucent glass background
        border: Border(
          bottom: BorderSide(color: AppTheme.primaryCyan.withValues(alpha: 0.25), width: 1.2),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: const Icon(Icons.arrow_back_rounded,
                  color: Colors.white70, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Hero(
            tag: 'logo',
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.primaryCyan.withValues(alpha: 0.35), width: 1.5),
                boxShadow: [
                  BoxShadow(color: AppTheme.primaryCyan.withValues(alpha: 0.15), blurRadius: 8, spreadRadius: 1),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: _buildDynamicLogo(instrument, size: 44),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Instrument name (bold)
          Text(
            AppConstants.instrumentNames[instrument] ?? instrument,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(width: 8),
          // LIVE badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: AppTheme.bullColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppTheme.bullColor.withValues(alpha: 0.4), width: 0.8),
            ),
            child: const Text('LIVE',
                style: TextStyle(
                    color: AppTheme.bullColor,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0)),
          ),
          // NSE badge for individual stocks
          if (!AppConstants.instruments.contains(instrument)) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: AppTheme.accentPurple.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppTheme.accentPurple.withValues(alpha: 0.4), width: 0.8),
              ),
              child: const Text('NSE',
                  style: TextStyle(
                      color: AppTheme.accentPurple,
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0)),
            ),
          ],
          // Separator
          const SizedBox(width: 12),
          Container(width: 1, height: 22, color: Colors.white24),
          const SizedBox(width: 12),
          // Live price
          if (displayPrice > 0)
            Text(
              '₹${displayPrice.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: AppTheme.primaryCyan,
                letterSpacing: -0.5,
                shadows: [
                  Shadow(color: AppTheme.primaryCyan, blurRadius: 10),
                ],
              ),
            ),
          const Spacer(),
          // Live news indicator dot
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFF3B5C).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: const Color(0xFFFF3B5C).withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PulseDot(color: Color(0xFFFF3B5C)),
                SizedBox(width: 5),
                Text(
                  'LIVE',
                  style: TextStyle(
                    color: Color(0xFFFF3B5C),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicLogo(String symbol, {double size = 32}) {
    final cleanSymbol = StockLogos.cleanSymbol(symbol);
    
    // 1. Check local bundled assets first
    if (StockLogos.localAssets.containsKey(cleanSymbol)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.2),
        child: Image.asset(
          StockLogos.localAssets[cleanSymbol]!,
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (context, error, stackTrace) => _buildDefaultLogo(size),
        ),
      );
    }
    
    // 2. Network: Clearbit primary → Google Favicons fallback
    final clearbitUrl = StockLogos.getLogoUrl(cleanSymbol);
    final googleUrl = StockLogos.getFallbackLogoUrl(cleanSymbol);
    
    if (clearbitUrl.isNotEmpty) {
      return _NewsLogoWithFallback(
        primaryUrl: clearbitUrl,
        fallbackUrl: googleUrl,
        size: size,
        defaultWidget: _buildDefaultLogo(size),
      );
    }
    
    // 3. App logo fallback
    return _buildDefaultLogo(size);
  }

  Widget _buildDefaultLogo(double size) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.2),
      child: Image.asset(
        'assets/images/logo_bigshot.jpg',
        fit: BoxFit.cover,
        width: size,
        height: size,
        errorBuilder: (context, error, stackTrace) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppTheme.cardColor,
            borderRadius: BorderRadius.circular(size * 0.2),
          ),
          child: const Icon(Icons.show_chart_rounded, color: AppTheme.primaryCyan, size: 16),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: AppTheme.bgColor,
      child: TabBar(
        controller: _tabController,
        indicatorColor: const Color(0xFF00C9A7),
        indicatorWeight: 2,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.white.withValues(alpha: 0.05),
        labelColor: const Color(0xFF00C9A7),
        unselectedLabelColor: Colors.white38,
        labelStyle: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
        tabs: const [
          Tab(text: 'MARKET PULSE'),
          Tab(text: 'WORLD ECO'),
          Tab(text: 'AI SENTIMENT'),
        ],
      ),
    );
  }

  // ─── MARKET PULSE TAB ───────────────────────────────────────────────────────

  Widget _buildMarketPulseTab() {
    final newsAsync = ref.watch(marketNewsProvider);
    final selectedInstrument = ref.watch(selectedInstrumentProvider);
    return newsAsync.when(
      loading: () => _buildLoader(),
      error: (e, _) => _buildError(
        'Market news unavailable',
        onRetry: () => ref.invalidate(marketNewsProvider),
      ),
      data: (items) {
        final filteredItems = _filterNewsForInstrument(items, selectedInstrument);
        return _buildNewsList(
          filteredItems,
          accentColor: const Color(0xFF00C9A7),
          emptyMessage: 'No market news available',
        );
      },
    );
  }

  List<NewsItem> _filterNewsForInstrument(List<NewsItem> allNews, String instrument) {
    if (instrument == AppConstants.nifty50 ||
        instrument == AppConstants.bankNifty ||
        instrument == AppConstants.finNifty ||
        instrument == 'SENSEX' ||
        instrument.isEmpty) {
      return allNews;
    }

    final String cleanSymbol = instrument.toUpperCase().trim();
    final List<String> keywords = [cleanSymbol];
    
    if (cleanSymbol == 'TCS') {
      keywords.addAll(['TATA CONSULTANCY SERVICES', 'TATA CONSULTANCY', 'TATA']);
    } else if (cleanSymbol == 'INFY') {
      keywords.addAll(['INFOSYS', 'INFY']);
    } else if (cleanSymbol == 'RELIANCE') {
      keywords.addAll(['RELIANCE INDUSTRIES', 'RELIANCE', 'RIL']);
    } else {
      final fullName = AppConstants.instrumentNames[instrument];
      if (fullName != null) {
        keywords.add(fullName.toUpperCase());
      }
    }

    final filtered = allNews.where((item) {
      final titleUpper = item.title.toUpperCase();
      final descriptionUpper = (item.description ?? '').toUpperCase();
      return keywords.any((kw) => titleUpper.contains(kw) || descriptionUpper.contains(kw));
    }).toList();

    if (filtered.isNotEmpty) {
      return filtered;
    }
    return allNews;
  }

  // ─── WORLD ECONOMY TAB ──────────────────────────────────────────────────────

  Widget _buildWorldEconomyTab() {
    final newsAsync = ref.watch(worldNewsProvider);
    return newsAsync.when(
      loading: () => _buildLoader(),
      error: (e, _) => _buildError(
        'World news unavailable',
        onRetry: () => ref.invalidate(worldNewsProvider),
      ),
      data: (items) => _buildNewsList(
        items,
        accentColor: const Color(0xFF2962FF),
        emptyMessage: 'No world economy news available',
      ),
    );
  }

  Widget _buildNewsList(
    List<NewsItem> items, {
    required Color accentColor,
    required String emptyMessage,
  }) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded,
                color: Colors.white24, size: 40),
            const SizedBox(height: 12),
            Text(
              emptyMessage,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: accentColor,
      backgroundColor: AppTheme.cardColor,
      onRefresh: () async {
        ref.invalidate(marketNewsProvider);
        ref.invalidate(worldNewsProvider);
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        itemCount: items.length,
        separatorBuilder: (_, __) =>
            const SizedBox(height: 4),
        itemBuilder: (context, i) =>
            _buildCompactNewsCard(items[i], accentColor, index: i),
      ),
    );
  }

  Widget _buildCompactNewsCard(NewsItem item, Color accent,
      {required int index}) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _openLink(item.link);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Index number
            Container(
              width: 22,
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: accent.withValues(alpha: 0.5),
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title — max 2 lines
                  Text(
                    item.title,
                    style: TextStyle(
                      color: item.sentiment == 'positive'
                          ? const Color(0xFF00C9A7) // Green font
                          : (item.sentiment == 'negative'
                              ? const Color(0xFFFF3B5C) // Red font
                              : Colors.white), // Neutral
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  // Source + time row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                              color: accent.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          item.source.toUpperCase(),
                          style: TextStyle(
                            color: accent,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatTime(item.pubDate),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 9,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.open_in_new_rounded,
                        color: Colors.white.withValues(alpha: 0.2),
                        size: 12,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── AI SENTIMENT TAB ───────────────────────────────────────────────────────

  Widget _buildAiSentimentTab() {
    if (!_aiRequested) {
      return _buildAiLanding();
    }

    final marketAsync = ref.watch(marketNewsProvider);
    final worldAsync = ref.watch(worldNewsProvider);

    // Wait for at least market news to have data
    final hasData = marketAsync.hasValue || worldAsync.hasValue;
    if (!hasData) return _buildLoader();

    final sentimentAsync = ref.watch(aiSentimentProvider);
    return sentimentAsync.when(
      loading: () => _buildAiLoadingState(),
      error: (e, _) => _buildError(
        'AI analysis failed. Check your internet connection.',
        onRetry: () {
          ref.invalidate(aiSentimentProvider);
        },
      ),
      data: (data) => _buildAiResult(data),
    );
  }

  Widget _buildAiLanding() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Glowing brain icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF764BA2).withValues(alpha: 0.3),
                    Colors.transparent,
                  ],
                ),
                border: Border.all(
                    color: const Color(0xFF764BA2).withValues(alpha: 0.4),
                    width: 1.5),
              ),
              child: const Center(
                child: Icon(Icons.psychology_rounded,
                    color: Color(0xFF764BA2), size: 36),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'AI SENTIMENT ENGINE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Powered by Google Gemini AI.\nAnalyzes live headlines to determine overall market bias.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                setState(() => _aiRequested = true);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF764BA2), Color(0xFF2962FF)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF764BA2).withValues(alpha: 0.3),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'RUN AI ANALYSIS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _SpinningAiLogo(),
          const SizedBox(height: 20),
          Text(
            'GEMINI IS ANALYZING HEADLINES...',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Scanning live market feeds',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.25),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiResult(Map<String, dynamic> data) {
    final sentiment = (data['sentiment'] as String? ?? 'NEUTRAL').toUpperCase();
    final outlook = data['outlook'] as String? ?? '';
    final triggers = (data['triggers'] as List<dynamic>?)
            ?.map((t) => t.toString())
            .toList() ??
        [];

    final Color sentimentColor;
    final IconData sentimentIcon;
    final String sentimentLabel;

    switch (sentiment) {
      case 'BULLISH':
        sentimentColor = const Color(0xFF00C9A7);
        sentimentIcon = Icons.trending_up_rounded;
        sentimentLabel = '🟢 BULLISH';
        break;
      case 'BEARISH':
        sentimentColor = const Color(0xFFFF3B5C);
        sentimentIcon = Icons.trending_down_rounded;
        sentimentLabel = '🔴 BEARISH';
        break;
      case 'VOLATILITY':
        sentimentColor = const Color(0xFFFFD700);
        sentimentIcon = Icons.electric_bolt_rounded;
        sentimentLabel = '⚡ VOLATILE';
        break;
      default:
        sentimentColor = const Color(0xFF94A3B8);
        sentimentIcon = Icons.remove_rounded;
        sentimentLabel = '⚪ NEUTRAL';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sentiment Dial Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: sentimentColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: sentimentColor.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                // Glowing sentiment circle
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: sentimentColor.withValues(alpha: 0.12),
                    border: Border.all(
                        color: sentimentColor.withValues(alpha: 0.5),
                        width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: sentimentColor.withValues(alpha: 0.25),
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Icon(sentimentIcon,
                      color: sentimentColor, size: 36),
                ),
                const SizedBox(height: 12),
                Text(
                  sentimentLabel,
                  style: TextStyle(
                    color: sentimentColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'AI MARKET SENTIMENT',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 9,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Market Outlook
          if (outlook.isNotEmpty) ...[
            _buildSectionLabel('MARKET OUTLOOK'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.cardColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Text(
                outlook,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Key Triggers
          if (triggers.isNotEmpty) ...[
            _buildSectionLabel('KEY TRIGGERS'),
            const SizedBox(height: 8),
            ...triggers.asMap().entries.map((entry) {
              final colors = [
                const Color(0xFF00C9A7),
                const Color(0xFF2962FF),
                const Color(0xFFFFD700),
              ];
              final color = colors[entry.key % colors.length];
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.cardColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border(
                      left: BorderSide(color: color, width: 3),
                      right: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                      top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                      bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${entry.key + 1}',
                            style: TextStyle(
                              color: color,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          entry.value,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 14),
          ],

          // Re-run button
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              ref.invalidate(aiSentimentProvider);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(
                    color: const Color(0xFF764BA2).withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(10),
                color: const Color(0xFF764BA2).withValues(alpha: 0.08),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.refresh_rounded,
                      color: Color(0xFF764BA2), size: 16),
                  SizedBox(width: 8),
                  Text(
                    'REFRESH ANALYSIS',
                    style: TextStyle(
                      color: Color(0xFF764BA2),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.35),
        fontSize: 9,
        fontWeight: FontWeight.w900,
        letterSpacing: 2,
      ),
    );
  }

  Widget _buildLoader() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF00C9A7),
            ),
          ),
          SizedBox(height: 12),
          Text(
            'FETCHING LIVE FEEDS...',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String message, {required VoidCallback onRetry}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.signal_wifi_off_rounded,
              color: Colors.white24, size: 36),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(
                    color: const Color(0xFF00C9A7).withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'RETRY',
                style: TextStyle(
                  color: Color(0xFF00C9A7),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── HELPER WIDGETS ──────────────────────────────────────────────────────────

/// Blinking pulse dot (used in LIVE badge)
class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Spinning AI logo for the loading state
class _SpinningAiLogo extends StatefulWidget {
  const _SpinningAiLogo();

  @override
  State<_SpinningAiLogo> createState() => _SpinningAiLogoState();
}

class _SpinningAiLogoState extends State<_SpinningAiLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Transform.rotate(
        angle: _ctrl.value * 2 * math.pi,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF764BA2).withValues(alpha: 0.7),
              width: 2.5,
            ),
          ),
          child: const Icon(
            Icons.psychology_rounded,
            color: Color(0xFF764BA2),
            size: 28,
          ),
        ),
      ),
    );
  }
}

/// A smart network image widget that tries [primaryUrl] first (Clearbit),
/// then automatically falls back to [fallbackUrl] (Google Favicons),
/// and finally shows [defaultWidget] if both fail.
class _NewsLogoWithFallback extends StatefulWidget {
  final String primaryUrl;
  final String fallbackUrl;
  final double size;
  final Widget defaultWidget;

  const _NewsLogoWithFallback({
    required this.primaryUrl,
    required this.fallbackUrl,
    required this.size,
    required this.defaultWidget,
  });

  @override
  State<_NewsLogoWithFallback> createState() => _NewsLogoWithFallbackState();
}

class _NewsLogoWithFallbackState extends State<_NewsLogoWithFallback> {
  bool _primaryFailed = false;
  bool _fallbackFailed = false;

  @override
  void didUpdateWidget(_NewsLogoWithFallback oldWidget) {
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
      borderRadius: BorderRadius.circular(widget.size * 0.2),
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
            // Clearbit failed → try Google Favicons
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _primaryFailed = true);
            });
          } else {
            // Google Favicons also failed → show app default
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _fallbackFailed = true);
            });
          }
          // Show a placeholder while switching
          return Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: const Color(0xFF0C1420),
              borderRadius: BorderRadius.circular(widget.size * 0.2),
            ),
          );
        },
      ),
    );
  }
}

