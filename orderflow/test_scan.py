import os

desktop_dir = r"C:\Users\PUTIN\Desktop"

for root, dirs, files in os.walk(desktop_dir):
    if any(p in root.lower() for p in ["node_modules", "build", ".git", ".dart_tool"]):
        continue
    for f in files:
        if "chart_screen.dart" in f.lower():
            path = os.path.join(root, f)
            print(f"Scanned: {path} | Size: {os.path.getsize(path)}")
            with open(path, "r", encoding="utf-8", errors="ignore") as file:
                header = file.read(1000)
            print(f"  Contains 'class ChartScreen': {'class ChartScreen' in header}")
            print(f"  Header starts with: {repr(header[:100])}")
