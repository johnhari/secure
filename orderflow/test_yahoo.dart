import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final now = DateTime.now().toLocal();
  DateTime candidate = DateTime(now.year, now.month, now.day);
  int n = 5;
  
  final List<DateTime> tradingDays = [];
  while (tradingDays.length < n) {
    if (candidate.weekday <= 5) {
      tradingDays.add(candidate);
    }
    candidate = candidate.subtract(const Duration(days: 1));
  }
  final cutoff = tradingDays.last;
  final period1 = cutoff.millisecondsSinceEpoch ~/ 1000;
  final period2 = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
  
  final url = Uri.parse(
    'https://query1.finance.yahoo.com/v8/finance/chart/^NSEI'
    '?interval=5m&period1=$period1&period2=$period2',
  );
  
  print("URL: $url");
  try {
    final response = await http.get(url);
    print("Status: ${response.statusCode}");
    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      var result = data['chart']['result'][0];
      print("Timestamps: ${result['timestamp']?.length}");
    } else {
      print("Body: ${response.body}");
    }
  } catch(e) {
    print("Error: $e");
  }
}
