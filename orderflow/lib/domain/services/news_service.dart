import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:collection/collection.dart';
import '../../data/models/news_item.dart';

class NewsService {
  final http.Client _client;
  
  NewsService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetch and parse news from RSS feed, then curate using Gemini AI if available
  Future<List<NewsItem>> fetchNews(String category, [String? symbol]) async {
    List<NewsItem> rawItems = [];
    try {
      rawItems = await _fetchNewsFromRss(category, symbol, '1d');
      if (rawItems.isEmpty) {
        rawItems = await _fetchNewsFromRss(category, symbol, '7d');
      }
    } catch (e) {
      print('NewsService: RSS fetch error: $e');
    }

    if (rawItems.isEmpty) {
      rawItems = _getFallbackNews(category, symbol);
    }

    // Try curating with AI if API key is available
    try {
      final aiItems = await curateNewsWithAI(rawItems, category, symbol);
      if (aiItems.isNotEmpty) {
        return aiItems;
      }
    } catch (e) {
      print('NewsService: AI Curation failed, returning raw news: $e');
    }

    // Apply basic sentiment to raw/fallback items if AI was not used/failed
    return rawItems.map((n) {
      return NewsItem(
        title: n.title,
        description: n.description,
        link: n.link,
        pubDate: n.pubDate,
        source: n.source,
        category: n.category,
        sentiment: _analyzeBasicSentiment(n.title, n.description),
      );
    }).toList();
  }

  /// Basic sentiment analyzer for fallback raw news
  String _analyzeBasicSentiment(String title, String description) {
    final text = '$title $description'.toLowerCase();
    
    // Negative keywords
    final negativeKeywords = [
      'down', 'fall', 'drop', 'slump', 'crash', 'bearish', 'losses', 'plunge',
      'decline', 'dip', 'deficit', 'inflation', 'hike', 'crisis', 'panic',
      'red', 'sell-off', 'hit', 'slipped', 'negative', 'concern', 'weaken',
      'lower', 'recession', 'warn', 'shocker'
    ];
    
    // Positive keywords
    final positiveKeywords = [
      'up', 'rise', 'gain', 'surge', 'rally', 'bullish', 'profit', 'jump',
      'grow', 'climb', 'positive', 'green', 'high', 'recovery', 'boost',
      'expand', 'strong', 'gains', 'optimism', 'beat'
    ];

    int score = 0;
    for (final kw in negativeKeywords) {
      if (text.contains(kw)) score--;
    }
    for (final kw in positiveKeywords) {
      if (text.contains(kw)) score++;
    }

    if (score < 0) return 'negative';
    if (score > 0) return 'positive';
    return 'neutral';
  }

  /// Curate, filter and summarize news using Gemini AI
  Future<List<NewsItem>> curateNewsWithAI(List<NewsItem> rawNews, String category, String? symbol) async {
    if (rawNews.isEmpty) return [];

    try {
      // 1. Fetch Gemini API key from Firebase Firestore config
      final configSnapshot = await FirebaseFirestore.instance
          .collection('global_config')
          .doc('active_configuration')
          .get();
      final config = configSnapshot.data() ?? {};
      final apiKey = config['geminiApiKey'] as String? ?? '';

      if (apiKey.isEmpty) {
        print('NewsService: No Gemini API key for curation, skipping AI.');
        return [];
      }

      // Prepare prompt payload
      final headlinesJson = jsonEncode(rawNews.map((n) => {
        'title': n.title,
        'description': n.description,
        'source': n.source,
      }).toList());

      String filterCriteria = '';
      if (category == 'world') {
        filterCriteria = 'Keep ONLY highly important world macroeconomic news (e.g., inflation, interest rates, central banks, global currency/oil crisis). Filter out minor local/political news.';
      } else {
        final target = symbol ?? 'Stock Market';
        filterCriteria = 'Keep ONLY news directly related to $target or general stock market indices and trading activity. Filter out irrelevant general corporate press releases.';
      }

      final prompt = '''
You are an AI financial editor. Curate, filter, and rewrite the following list of raw financial news items:
$headlinesJson

Filter Criteria:
$filterCriteria

For the items that pass the filter criteria:
1. Simplify and rewrite the title to be punchy and professional.
2. Summarize the description into exactly 1 concise sentence.
3. Preserve or clean the source name.
4. Classify the sentiment of the headline as either "positive", "negative", or "neutral".

Return the curated list in JSON format matching the schema:
[
  {
    "title": "Cleaned Title",
    "description": "1 sentence description",
    "source": "Source Name",
    "sentiment": "positive", "negative", or "neutral"
  }
]

Return ONLY the JSON array of objects. Do not include markdown codeblocks or wrapper text.
''';

      // Call Gemini model
      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);
      final response = await model.generateContent([Content.text(prompt)]);
      
      var responseText = response.text ?? '';
      if (responseText.contains('```json')) {
        responseText = responseText.split('```json').last.split('```').first.trim();
      } else if (responseText.contains('```')) {
        responseText = responseText.split('```').last.split('```').first.trim();
      }

      final List<dynamic> parsed = jsonDecode(responseText);
      
      // Map back to NewsItem keeping original link and pubDate if matching
      final List<NewsItem> curatedItems = [];
      for (var i = 0; i < parsed.length; i++) {
        final map = parsed[i];
        final title = map['title'] as String? ?? '';
        final description = map['description'] as String? ?? '';
        final source = map['source'] as String? ?? '';
        final sentiment = map['sentiment'] as String? ?? 'neutral';
        
        // Find matching raw news item to preserve link/date
        final matchingRaw = rawNews.firstWhereOrNull(
          (r) => r.title.toLowerCase().contains(title.split(' ').first.toLowerCase())
        ) ?? rawNews[i % rawNews.length];

        curatedItems.add(NewsItem(
          title: title,
          description: description,
          link: matchingRaw.link,
          pubDate: matchingRaw.pubDate,
          source: source,
          category: category,
          sentiment: sentiment.toLowerCase().trim(),
        ));
      }

      return curatedItems;
    } catch (e) {
      print('NewsService: AI curation error: $e');
      return [];
    }
  }

  Future<List<NewsItem>> _fetchNewsFromRss(String category, String? symbol, String timeRange) async {
    String query = 'stock+market+india+nifty+(breaking+OR+major+OR+crash+OR+surge+OR+policy+OR+RBI)+when:$timeRange';
    if (category == 'world') {
      query = 'world+economy+markets+fed+inflation+(breaking+OR+major+OR+crisis+OR+crash+OR+rate)+when:$timeRange';
    } else if (symbol != null && symbol.isNotEmpty) {
      final cleanSymbol = symbol.toUpperCase().trim();
      if (cleanSymbol == 'NIFTY50' || cleanSymbol == 'NIFTY') {
        query = 'nifty+50+india+(market+OR+breaking+OR+crash+OR+surge+OR+rbi)+when:$timeRange';
      } else if (cleanSymbol == 'BANKNIFTY' || cleanSymbol == 'BANK NIFTY') {
        query = 'bank+nifty+india+(market+OR+breaking+OR+crash+OR+surge+OR+rbi)+when:$timeRange';
      } else if (cleanSymbol == 'FINNIFTY' || cleanSymbol == 'FIN NIFTY') {
        query = 'fin+nifty+india+(market+OR+breaking+OR+crash+OR+surge)+when:$timeRange';
      } else if (cleanSymbol == 'MIDCAPNIFTY' || cleanSymbol == 'MIDCAP NIFTY') {
        query = 'midcap+nifty+india+(market+OR+breaking+OR+crash+OR+surge)+when:$timeRange';
      } else {
        query = '${Uri.encodeComponent(cleanSymbol)}+(stock+OR+share+OR+market+OR+quarterly+OR+dividend)+india+when:$timeRange';
      }
    }

    final url = 'https://news.google.com/rss/search?q=$query&hl=en-IN&gl=IN&ceid=IN:en';
    
    final response = await _client.get(Uri.parse(url), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    }).timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      return [];
    }

    return _parseRss(response.body, category);
  }

  List<NewsItem> _getFallbackNews(String category, String? symbol) {
    final now = DateTime.now();
    if (category == 'world') {
      return [
        NewsItem(
          title: 'Global markets closely watch US Federal Reserve interest rate decision',
          description: 'Investors look for signals on inflation and monetary policy easing.',
          link: 'https://finance.yahoo.com',
          pubDate: now.subtract(const Duration(hours: 2)),
          source: 'Bloomberg',
          category: 'world',
        ),
        NewsItem(
          title: 'Inflation concerns ease as commodity prices stabilize globally',
          description: 'Stable oil and gas prices help alleviate global market supply pressure.',
          link: 'https://reuters.com',
          pubDate: now.subtract(const Duration(hours: 4)),
          source: 'Reuters',
          category: 'world',
        ),
        NewsItem(
          title: 'European stocks climb on positive corporate earnings reports',
          description: 'Major indexes close higher as retail and tech sectors rally.',
          link: 'https://cnbc.com',
          pubDate: now.subtract(const Duration(hours: 6)),
          source: 'CNBC',
          category: 'world',
        ),
      ];
    }

    final cleanSymbol = (symbol ?? 'NIFTY50').toUpperCase().trim();
    if (cleanSymbol == 'NIFTY50' || cleanSymbol == 'NIFTY') {
      return [
        NewsItem(
          title: 'Nifty 50 trades in tight consolidation range; institutional buyers active at key support',
          description: 'Market experts point to strong support levels forming near current zones.',
          link: 'https://moneycontrol.com',
          pubDate: now.subtract(const Duration(minutes: 30)),
          source: 'Moneycontrol',
          category: 'market',
        ),
        NewsItem(
          title: 'Options data suggests strong resistance at upper boundary; delta divergence detected',
          description: 'Call writers active at key strikes while put writing suggests support below.',
          link: 'https://economictimes.indiatimes.com',
          pubDate: now.subtract(const Duration(hours: 2)),
          source: 'Economic Times',
          category: 'market',
        ),
      ];
    } else if (cleanSymbol == 'BANKNIFTY' || cleanSymbol == 'BANK NIFTY') {
      return [
        NewsItem(
          title: 'Bank Nifty showing selling pressure near intraday high; retail trap identified',
          description: 'Heavy distribution blocks noted at key levels before sharp reversal.',
          link: 'https://moneycontrol.com',
          pubDate: now.subtract(const Duration(minutes: 45)),
          source: 'Moneycontrol',
          category: 'market',
        ),
        NewsItem(
          title: 'Institutional block deals reported in major private banking stocks',
          description: 'Large order flow volumes observed at key price action blocks.',
          link: 'https://livemint.com',
          pubDate: now.subtract(const Duration(hours: 3)),
          source: 'Livemint',
          category: 'market',
        ),
      ];
    } else {
      return [
        NewsItem(
          title: 'Institutional accumulation detected on $cleanSymbol at current price level',
          description: 'Orderflow buy delta shows rising institutional buying participation.',
          link: 'https://moneycontrol.com',
          pubDate: now.subtract(const Duration(minutes: 15)),
          source: 'Moneycontrol',
          category: 'market',
        ),
        NewsItem(
          title: 'Volume expansion on $cleanSymbol points to potential breakout',
          description: 'Unusual buy volumes detected on orderflow candles.',
          link: 'https://economictimes.indiatimes.com',
          pubDate: now.subtract(const Duration(hours: 1)),
          source: 'Economic Times',
          category: 'market',
        ),
      ];
    }
  }

  /// Parse Google News RSS Feed XML
  List<NewsItem> _parseRss(String xmlBody, String category) {
    final List<NewsItem> items = [];
    final itemRegex = RegExp(r'<item>([\s\S]*?)</item>');
    final titleRegex = RegExp(r'<title>([\s\S]*?)</title>');
    final linkRegex = RegExp(r'<link>([\s\S]*?)</link>');
    final dateRegex = RegExp(r'<pubDate>([\s\S]*?)</pubDate>');
    final descRegex = RegExp(r'<description>([\s\S]*?)</description>');
    final sourceRegex = RegExp(r'<source[^>]*>([\s\S]*?)</source>');

    final matches = itemRegex.allMatches(xmlBody);
    for (final match in matches) {
      final content = match.group(1) ?? '';
      
      var title = titleRegex.firstMatch(content)?.group(1) ?? 'No Title';
      var link = linkRegex.firstMatch(content)?.group(1) ?? '';
      var pubDateStr = dateRegex.firstMatch(content)?.group(1) ?? '';
      var description = descRegex.firstMatch(content)?.group(1) ?? '';
      var source = sourceRegex.firstMatch(content)?.group(1) ?? 'News';

      title = _cleanXmlData(title);
      link = _cleanXmlData(link);
      pubDateStr = _cleanXmlData(pubDateStr);
      description = _cleanXmlData(description);
      source = _cleanXmlData(source);

      // Extract real source from Title if Google News appends it: "Headline - Source Name"
      if (title.contains(' - ')) {
        final parts = title.split(' - ');
        source = parts.last;
        title = parts.sublist(0, parts.length - 1).join(' - ');
      }

      // Remove HTML tags from description
      description = description.replaceAll(RegExp(r'<[^>]*>'), '');
      if (description.length > 180) {
        description = '${description.substring(0, 177)}...';
      }

      // If description is empty or too short, use title
      if (description.isEmpty || description.length < 5) {
        description = title;
      }

      DateTime pubDate;
      try {
        // Fallback-friendly date parsing
        pubDate = DateTime.tryParse(pubDateStr) ?? DateTime.now();
      } catch (_) {
        pubDate = DateTime.now();
      }

      items.add(NewsItem(
        title: title,
        description: description,
        link: link,
        pubDate: pubDate,
        source: source,
        category: category,
      ));
    }
    return items;
  }

  String _cleanXmlData(String val) {
    var s = val.trim();
    if (s.startsWith('<![CDATA[') && s.endsWith(']]>')) {
      s = s.substring(9, s.length - 3).trim();
    }
    // Clean common HTML entities
    s = s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&rsquo;', "'");
    return s;
  }

  /// Compile latest headlines and call Gemini for market sentiment analysis
  Future<Map<String, dynamic>> analyzeSentiment(List<NewsItem> newsItems) async {
    try {
      if (newsItems.isEmpty) {
        return {
          'sentiment': 'NEUTRAL',
          'outlook': 'No recent news articles found to compile sentiment analysis.',
          'triggers': ['Markets waiting for major indicators'],
        };
      }

      // 1. Fetch Gemini API key from Firebase Firestore config
      final configSnapshot = await FirebaseFirestore.instance
          .collection('global_config')
          .doc('active_configuration')
          .get();
      final config = configSnapshot.data() ?? {};
      final apiKey = config['geminiApiKey'] as String? ?? '';

      if (apiKey.isEmpty) {
        return {
          'sentiment': 'VOLATILITY',
          'outlook': 'Gemini AI Sentiment analysis is currently offline. Please configure API key in settings.',
          'triggers': ['Macroeconomic events pending', 'Corporate earnings seasons ongoing'],
        };
      }

      // 2. Prepare headlines prompt
      final headlines = newsItems.take(12).map((item) => '- [${item.source}] ${item.title}').join('\n');
      
      final prompt = '''
You are an expert Wall Street financial analyst and market macro-economist.
Analyze the following recent stock market and business headlines:
$headlines

Based on these headlines, return a JSON response summarizing the overall sentiment and triggers.
Return ONLY a valid JSON object in this exact schema, without any markdown backticks or wrappers:
{
  "sentiment": "BULLISH", "BEARISH", "NEUTRAL" or "VOLATILITY",
  "outlook": "A punchy 1-2 sentence market outlook summary.",
  "triggers": [
    "Key trigger 1 description",
    "Key trigger 2 description",
    "Key trigger 3 description"
  ]
}
''';

      // 3. Call Gemini API
      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);
      final response = await model.generateContent([Content.text(prompt)]);
      
      var responseText = response.text ?? '';
      
      // Clean up markdown codeblocks if Gemini included them
      if (responseText.contains('```json')) {
        responseText = responseText.split('```json').last.split('```').first.trim();
      } else if (responseText.contains('```')) {
        responseText = responseText.split('```').last.split('```').first.trim();
      }

      final Map<String, dynamic> result = jsonDecode(responseText);
      return result;
    } catch (e) {
      print('NewsService: AI Sentiment analysis failed: $e');
      return {
        'sentiment': 'NEUTRAL',
        'outlook': 'Failed to compile AI Sentiment summary due to network timeout or token limits.',
        'triggers': ['Error compiling AI summary', 'Please try again in a few seconds'],
      };
    }
  }
}
