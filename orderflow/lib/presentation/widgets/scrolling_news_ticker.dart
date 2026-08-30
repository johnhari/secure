import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/models/news_item.dart';

class ScrollingNewsTicker extends StatefulWidget {
  final List<NewsItem> newsItems;
  final String? breakingMessage;
  final double height;

  const ScrollingNewsTicker({
    super.key,
    required this.newsItems,
    this.breakingMessage,
    this.height = 28,
  });

  @override
  State<ScrollingNewsTicker> createState() => _ScrollingNewsTickerState();
}

class _ScrollingNewsTickerState extends State<ScrollingNewsTicker>
    with SingleTickerProviderStateMixin {
  late ScrollController _scrollController;
  Timer? _scrollTimer;
  double _offset = 0;
  final double _speed = 0.6; // pixels per tick
  final int _tickMs = 16; // ~60fps

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _startScrolling();
  }

  void _startScrolling() {
    _scrollTimer?.cancel();
    _scrollTimer = Timer.periodic(Duration(milliseconds: _tickMs), (t) {
      if (!mounted || !_scrollController.hasClients) return;
      final maxExtent = _scrollController.position.maxScrollExtent;
      if (maxExtent <= 0) return;
      _offset += _speed;
      if (_offset >= maxExtent) {
        _offset = 0;
      }
      _scrollController.jumpTo(_offset);
    });
  }

  @override
  void didUpdateWidget(ScrollingNewsTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.newsItems != widget.newsItems ||
        oldWidget.breakingMessage != widget.breakingMessage) {
      _offset = 0;
    }
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  List<NewsTickerItem> _buildTickerItems() {
    final items = <NewsTickerItem>[];
    if (widget.breakingMessage != null && widget.breakingMessage!.isNotEmpty) {
      items.add(NewsTickerItem(
        text: '🔴 BREAKING: ${widget.breakingMessage!}',
        sentiment: 'negative',
        isBreaking: true,
      ));
    }
    for (final item in widget.newsItems) {
      items.add(NewsTickerItem(
        text: '${_sourceEmoji(item.source)} ${item.title}',
        sentiment: item.sentiment,
        isBreaking: false,
      ));
    }
    // Duplicate so the ticker loops seamlessly
    if (items.isNotEmpty) {
      items.addAll(List.from(items));
    }
    return items;
  }

  String _sourceEmoji(String source) {
    final s = source.toLowerCase();
    if (s.contains('economic') || s.contains('times')) return '📰';
    if (s.contains('moneycontrol') || s.contains('money')) return '💹';
    if (s.contains('bloomberg')) return '📊';
    if (s.contains('reuters')) return '📡';
    if (s.contains('cnbc')) return '📺';
    if (s.contains('mint')) return '🪙';
    if (s.contains('business')) return '💼';
    return '📌';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.newsItems.isEmpty && (widget.breakingMessage?.isEmpty ?? true)) {
      return const SizedBox.shrink();
    }

    final tickerItems = _buildTickerItems();
    final hasBreaking =
        widget.breakingMessage != null && widget.breakingMessage!.isNotEmpty;

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0F1A),
        border: Border.symmetric(
          horizontal: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Row(
        children: [
          // Left label badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            height: double.infinity,
            decoration: BoxDecoration(
              color: hasBreaking
                  ? const Color(0xFFFF3B5C).withValues(alpha: 0.9)
                  : const Color(0xFF00C9A7).withValues(alpha: 0.15),
              border: Border(
                right: BorderSide(
                  color: hasBreaking
                      ? const Color(0xFFFF3B5C).withValues(alpha: 0.5)
                      : const Color(0xFF00C9A7).withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Center(
              child: Text(
                hasBreaking ? 'BREAKING' : 'LIVE NEWS',
                style: TextStyle(
                  color: hasBreaking ? Colors.white : const Color(0xFF00C9A7),
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),

          // Scrolling headlines
          Expanded(
            child: ListView.separated(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: tickerItems.length,
              separatorBuilder: (_, __) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: Container(
                    width: 3,
                    height: 3,
                    decoration: const BoxDecoration(
                      color: Color(0xFF00C9A7),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              itemBuilder: (context, i) {
                final tickerItem = tickerItems[i];
                Color textColor;
                if (tickerItem.isBreaking) {
                  textColor = const Color(0xFFFF3B5C);
                } else if (tickerItem.sentiment == 'positive') {
                  textColor = const Color(0xFF00C9A7); // Green font
                } else if (tickerItem.sentiment == 'negative') {
                  textColor = const Color(0xFFFF3B5C); // Red font
                } else {
                  textColor = Colors.white.withValues(alpha: 0.75); // Neutral
                }

                return Center(
                  child: Text(
                    tickerItem.text,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 10,
                      fontWeight: tickerItem.isBreaking ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    softWrap: false,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class NewsTickerItem {
  final String text;
  final String sentiment;
  final bool isBreaking;

  NewsTickerItem({
    required this.text,
    required this.sentiment,
    required this.isBreaking,
  });
}
