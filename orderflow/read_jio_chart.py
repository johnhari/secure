import os

path = r"C:\Users\PUTIN\Desktop\JIO\JC-Jeevanan-610d\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\chart_screen.dart"

if not os.path.exists(path):
    print("File not found")
    exit(1)

with open(path, "r", encoding="utf-8", errors="ignore") as f:
    lines = f.readlines()

print(f"Total lines: {len(lines)}")
for i, line in enumerate(lines):
    if "_AnimatedOrderflowCounter" in line or "_buildSpecialEffectLayers" in line:
        print(f"Line {i+1}: {line.strip()}")
        # print surrounding 5 lines
        start = max(0, i - 10)
        end = min(len(lines), i + 25)
        print(f"--- Context (Lines {start+1} to {end}) ---")
        for idx in range(start, end):
            print(f"{idx+1}: {lines[idx]}", end="")
        print("\n-------------------------------\n")
        break
