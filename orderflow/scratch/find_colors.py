with open(r'c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\chart_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

for idx in range(2440, 2900):
    line = lines[idx]
    if 'color' in line.lower() or 'decoration' in line.lower() or 'apptheme.' in line.lower():
        print(f"Line {idx+1}: {line.strip()}")
