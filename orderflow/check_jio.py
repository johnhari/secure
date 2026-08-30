import os
import datetime

jio_dir = r"C:\Users\PUTIN\Desktop\JIO\JC-Jeevanan-610d\ADVANCEORDERFLOW"
print("Scanning JIO directory:", jio_dir)

if not os.path.exists(jio_dir):
    print("JIO directory does not exist")
    exit(1)

# List subdirectories and files, their sizes and modification times
for root, dirs, files in os.walk(jio_dir):
    if any(p in root.lower() for p in ["node_modules", "build", ".git", ".dart_tool"]):
        continue
    print(f"\nRoot: {root}")
    for d in dirs:
        if d in ["node_modules", "build", ".git", ".dart_tool"]:
            continue
        print(f"  [DIR] {d}")
    for f in files:
        path = os.path.join(root, f)
        mtime = os.path.getmtime(path)
        dt = datetime.datetime.fromtimestamp(mtime)
        print(f"  [FILE] {f} (Size: {os.path.getsize(path)} bytes, Modified: {dt})")
