class NewsItem {
  final String title;
  final String description;
  final String link;
  final DateTime pubDate;
  final String source;
  final String category; // 'market' or 'world'
  final String sentiment; // 'positive', 'negative', or 'neutral'

  const NewsItem({
    required this.title,
    required this.description,
    required this.link,
    required this.pubDate,
    required this.source,
    required this.category,
    this.sentiment = 'neutral',
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'link': link,
      'pubDate': pubDate.millisecondsSinceEpoch,
      'source': source,
      'category': category,
      'sentiment': sentiment,
    };
  }

  factory NewsItem.fromJson(Map<String, dynamic> json) {
    return NewsItem(
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      link: json['link'] as String? ?? '',
      pubDate: DateTime.fromMillisecondsSinceEpoch(json['pubDate'] as int? ?? DateTime.now().millisecondsSinceEpoch),
      source: json['source'] as String? ?? '',
      category: json['category'] as String? ?? '',
      sentiment: json['sentiment'] as String? ?? 'neutral',
    );
  }
}
