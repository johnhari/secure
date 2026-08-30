import os
import zipfile

desktop_dir = r"C:\Users\PUTIN\Desktop"
print("Scanning Desktop for chart_screen.dart...")

# Search directories
for root, dirs, files in os.walk(desktop_dir):
    # Skip build directories or large node_modules to be fast
    if any(p in root.lower() for p in ["node_modules", "build", ".git", ".dart_tool"]):
        continue
    for f in files:
        if f == "chart_screen.dart":
            path = os.path.join(root, f)
            try:
                with open(path, "r", encoding="utf-8", errors="ignore") as file:
                    lines = file.readlines()
                print(f"Found file: {path} | Size: {os.path.getsize(path)} bytes | Lines: {len(lines)}")
            except Exception as e:
                print(f"Found file (error reading): {path} | Error: {e}")

# Search zip files on desktop
for f in os.listdir(desktop_dir):
    if f.endswith(".zip") or f.endswith(".rar"):
        zip_path = os.path.join(desktop_dir, f)
        print(f"Scanning archive: {zip_path}")
        if f.endswith(".zip"):
            try:
                with zipfile.ZipFile(zip_path, 'r') as zip_ref:
                    for name in zip_ref.namelist():
                        if "chart_screen.dart" in name:
                            print(f"  Found in zip: {name}")
            except Exception as e:
                print(f"  Error reading zip {f}: {e}")
