
with open(r'c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\admin_panel_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# We want to keep up to line 3091 (which is the empty line after _buildStatCard)
# Then we want to keep the _randomizeValue method which starts at 3248
# But wait, I'll just rewrite the whole end part.
header = lines[:3092] # indices 0-3091 (line 3092 is index 3091)
footer = [
    "  int _randomizeValue(int base) {\n",
    "    if (base <= 0) return 0;\n",
    "    final random = math.Random();\n",
    "    final variance = (base * 0.15).toInt(); // 15% variance\n",
    "    if (variance == 0) return base;\n",
    "    \n",
    "    final change = random.nextInt(variance * 2 + 1) - variance;\n",
    "    int result = base + change;\n",
    "    \n",
    "    // Ensure it's not ending in 00, 000 etc.\n",
    "    if (result % 10 == 0) {\n",
    "      result += random.nextInt(9) + 1;\n",
    "    }\n",
    "    return result;\n",
    "  }\n",
    "}\n"
]

with open(r'c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\admin_panel_screen.dart', 'w', encoding='utf-8') as f:
    f.writelines(header)
    f.writelines(footer)
