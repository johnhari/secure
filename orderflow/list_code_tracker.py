import os
import datetime

dir_to_scan = r"C:\Users\PUTIN\.gemini\antigravity-ide\code_tracker\active\no_repo"
print("Scanning:", dir_to_scan)

if not os.path.exists(dir_to_scan):
    print("Directory does not exist")
    exit(1)

files = os.listdir(dir_to_scan)
print(f"Total files in directory: {len(files)}")

for f in files:
    if "chart" in f.lower() or "screen" in f.lower() or os.path.getsize(os.path.join(dir_to_scan, f)) > 150000:
        path = os.path.join(dir_to_scan, f)
        mtime = os.path.getmtime(path)
        dt = datetime.datetime.fromtimestamp(mtime)
        print(f"File: {f} | Size: {os.path.getsize(path)} bytes | Modified: {dt}")
