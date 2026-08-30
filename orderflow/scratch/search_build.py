path = r"c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\chart_screen.dart"
with open(path, "r", encoding="utf-8") as f:
    for i, line in enumerate(f):
        if "widget build" in line.lower() or "override" in line.lower():
            if "widget build" in line.lower():
                print(f"Line {i+1}: {line.strip()}")
