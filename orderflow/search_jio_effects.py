import os

jio_path = r"C:\Users\PUTIN\Desktop\JIO\JC-Jeevanan-610d\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\chart_screen.dart"

with open(jio_path, "r", encoding="utf-8", errors="ignore") as f:
    content = f.read()

lines = content.splitlines()
print(f"Searching JIO chart_screen.dart (Total lines: {len(lines)}) for effects...")

for i, line in enumerate(lines):
    if "effect" in line.lower() or "particle" in line.lower() or "layer" in line.lower():
        print(f"Line {i+1}: {line.strip()}")
