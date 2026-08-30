
with open(r'c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\admin_panel_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# find _buildStatCard end
# It ends at line 3090.
new_lines = lines[:3091] # keep up to index 3090 (line 3091)
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
    f.writelines(new_lines)
    f.writelines(footer)
