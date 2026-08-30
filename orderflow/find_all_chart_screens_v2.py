import os
import datetime

desktop_dir = r"C:\Users\PUTIN\Desktop"
term = "class ChartScreen"
print("Scanning Desktop recursively for files containing:", term)

found = 0
for root, dirs, files in os.walk(desktop_dir):
    # skip standard build/git dirs
    if any(p in root.lower() for p in ["node_modules", "build", ".git", ".dart_tool"]):
        continue
    for f in files:
        path = os.path.join(root, f)
        try:
            size = os.path.getsize(path)
            if size > 50 * 1024: # > 50KB
                with open(path, "r", encoding="utf-8", errors="ignore") as file:
                    content = file.read()
                if "class ChartScreen" in content:
                    mtime = os.path.getmtime(path)
                    dt = datetime.datetime.fromtimestamp(mtime)
                    print(f"Found file: {path} | Size: {size} bytes | Modified: {dt} | Lines: {len(content.splitlines())}")
                    found += 1
        except Exception as e:
            pass

print(f"Search finished. Found {found} files.")
