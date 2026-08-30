path = r"c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\chart_screen.dart"
with open(path, "rb") as f:
    content = f.read()

first_null = content.find(b'\x00')
if first_null != -1:
    # The 'c' of 'class StockSearchDelegate' starts at first_null - 1
    cut_index = first_null - 1
    print(f"Cutting file at byte index {cut_index}")
    clean_base = content[:cut_index]
    
    clean_code = """class StockSearchDelegate extends SearchDelegate<String?> {
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
      // Show History
      return FutureBuilder<SharedPreferences>(
        future: SharedPreferences.getInstance(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          final history = snapshot.data!.getStringList(_historyKey) ?? [];
          if (history.isEmpty) {
            return const Center(child: Text('Search Nifty 50 stocks', style: TextStyle(color: Colors.white54)));
          }
          return ListView.builder(
            itemCount: history.length,
            itemBuilder: (context, index) {
              final symbol = history[index];
              final name = NiftyStocks.stocks[symbol] ?? symbol;
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

    final results = NiftyStocks.search(query);
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
"""
    # Write as bytes, ensure clean newlines
    full_output = clean_base + b"\n\n" + clean_code.encode("utf-8")
    with open(path, "wb") as f:
        f.write(full_output)
    print("Success! File repaired.")
else:
    print("No null bytes found, file is already clean.")
