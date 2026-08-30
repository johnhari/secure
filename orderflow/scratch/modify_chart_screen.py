path = r"c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\chart_screen.dart"

with open(path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Add news_provider import
target1 = "import '../providers/auth_provider.dart';"
replacement1 = "import '../providers/auth_provider.dart';\nimport '../providers/news_provider.dart';"
if target1 in content:
    content = content.replace(target1, replacement1, 1)
    print("1. News provider import added successfully.")
else:
    print("1. FAILED: Could not find target1.")

# 2. Add newsAsync watch in build
target2 = "final selectedInstrument = ref.watch(selectedInstrumentProvider);"
replacement2 = "final selectedInstrument = ref.watch(selectedInstrumentProvider);\n    final newsAsync = ref.watch(marketNewsProvider);\n    final newsItems = newsAsync.value ?? [];"
if target2 in content:
    content = content.replace(target2, replacement2, 1)
    print("2. newsAsync watch added successfully.")
else:
    print("2. FAILED: Could not find target2.")

# 3. Pass newsItems to ScrollingNewsTicker
target3 = "const ScrollingNewsTicker(),"
replacement3 = "ScrollingNewsTicker(newsItems: newsItems),"
if target3 in content:
    content = content.replace(target3, replacement3, 1)
    print("3. ScrollingNewsTicker parameter fixed successfully.")
else:
    print("3. FAILED: Could not find target3.")

# 4. Declare local variables in _buildPriceHeader
target4 = """  Widget _buildPriceHeader(
    String instrument,
    CandleModel candle, 
    double animatedPrice,
    double change, 
    double changePercent, 
    double openPrice,
    bool isPointsFromOpenPositive, {
    int? candleCount,
  }) {
    return Container("""
replacement4 = """  Widget _buildPriceHeader(
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
    final pointsColor = isPointsFromOpenPositive ? AppTheme.bullColor : AppTheme.bearColor;

    return Container("""

# Standardize line endings to LF/CRLF for matching
normalized_content = content.replace("\r\n", "\n")
normalized_target4 = target4.replace("\r\n", "\n")
normalized_replacement4 = replacement4.replace("\r\n", "\n")

if normalized_target4 in normalized_content:
    normalized_content = normalized_content.replace(normalized_target4, normalized_replacement4, 1)
    # Write back in standard system encoding or normalized format
    content = normalized_content
    print("4. _buildPriceHeader variables added successfully.")
else:
    print("4. FAILED: Could not find target4.")

with open(path, "w", encoding="utf-8", newline="") as f:
    f.write(content)

print("Modification complete.")
