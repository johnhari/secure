import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/services/news_service.dart';
import '../../data/models/news_item.dart';
import 'instrument_provider.dart';

final newsServiceProvider = Provider<NewsService>((ref) {
  return NewsService();
});

final marketNewsProvider = FutureProvider<List<NewsItem>>((ref) async {
  final service = ref.watch(newsServiceProvider);
  
  // Set up a timer to auto-refresh news every 2 minutes
  final timer = Timer(const Duration(minutes: 2), () {
    ref.invalidateSelf();
  });
  ref.onDispose(() {
    timer.cancel();
  });
  
  return service.fetchNews('market');
});

final worldNewsProvider = FutureProvider<List<NewsItem>>((ref) async {
  final service = ref.watch(newsServiceProvider);
  
  // Set up a timer to auto-refresh news every 2 minutes
  final timer = Timer(const Duration(minutes: 2), () {
    ref.invalidateSelf();
  });
  ref.onDispose(() {
    timer.cancel();
  });
  
  return service.fetchNews('world');
});

final aiSentimentProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final service = ref.watch(newsServiceProvider);
  
  // Combine headlines for sentiment analysis
  final marketNews = ref.watch(marketNewsProvider).value ?? [];
  final worldNews = ref.watch(worldNewsProvider).value ?? [];
  
  // Take top 8 from market and top 4 from world for balanced analysis
  final List<NewsItem> combined = [];
  combined.addAll(marketNews.take(8));
  combined.addAll(worldNews.take(4));
  
  return service.analyzeSentiment(combined);
});
