import os
import datetime

appdata_local = os.environ.get("LOCALAPPDATA", r"C:\Users\PUTIN\AppData\Local")
appdata_roaming = os.environ.get("APPDATA", r"C:\Users\PUTIN\AppData\Roaming")

print("Searching AppData for Local History files...")

search_dirs = [appdata_local, appdata_roaming]
found_files = []

for base_dir in search_dirs:
    print("Scanning:", base_dir)
    for root, dirs, files in os.walk(base_dir):
        # Skip some huge directories to speed up
        if any(p in root.lower() for p in ["cache", "package cache", "npm", "pip", "temp", "tmp"]):
            continue
        for f in files:
            # Local history files in VS Code have random names but are in folders named 'History'
            if "history" in root.lower() and (f.endswith(".dart") or len(f) == 32 or len(f) == 40): # VS Code history files often have no extension and 40-char names
                path = os.path.join(root, f)
                try:
                    # Let's check if the file contains a unique chart_screen signature
                    size = os.path.getsize(path)
                    if 150000 <= size <= 250000: # chart_screen size is ~200KB
                        with open(path, "r", encoding="utf-8", errors="ignore") as file:
                            header = file.read(500)
                        if "class ChartScreen" in header or "class _ChartScreenState" in header:
                            mtime = os.path.getmtime(path)
                            dt = datetime.datetime.fromtimestamp(mtime)
                            print(f"Found history file: {path} | Size: {size} bytes | Modified: {dt}")
                            found_files.append((path, size, dt))
                except:
                    pass
            elif "chart_screen.dart" in f.lower():
                path = os.path.join(root, f)
                mtime = os.path.getmtime(path)
                dt = datetime.datetime.fromtimestamp(mtime)
                print(f"Found named file: {path} | Size: {os.path.getsize(path)} bytes | Modified: {dt}")

print("Search finished.")
