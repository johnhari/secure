import os
import datetime

backups_dir = r"C:\Users\PUTIN\AppData\Roaming\Antigravity IDE\Backups"
print("Scanning backups folder:", backups_dir)

if not os.path.exists(backups_dir):
    print("Backups directory does not exist")
    exit(1)

found = 0
for root, dirs, files in os.walk(backups_dir):
    for f in files:
        path = os.path.join(root, f)
        try:
            size = os.path.getsize(path)
            # Skip massive files
            if size > 1024 * 1024:
                continue
            with open(path, "r", encoding="utf-8", errors="ignore") as file:
                content = file.read()
            if "class ChartScreen" in content or "class _ChartScreenState" in content:
                mtime = os.path.getmtime(path)
                dt = datetime.datetime.fromtimestamp(mtime)
                print(f"Found match: {path} | Size: {size} bytes | Modified: {dt}")
                
                # Check for footprint or auto-zooming signature inside this file
                sig = "_AnimatedOrderflowCounter" in content or "auto-zooming" in content or "_buildViewModeButton" in content
                print(f"  Pulsing/footprint features signature present: {sig}")
                
                # Let's save a copy of this file to the workspace
                out_path = f"C:\\Users\\PUTIN\\Desktop\\ADVANCEORDERFLOW\\orderflow\\recovered_backup_{f}_{size}.dart"
                with open(out_path, "w", encoding="utf-8") as out_f:
                    out_f.write(content)
                print(f"  Saved copy to: {out_path}")
                
                found += 1
        except Exception as e:
            pass

print(f"Search finished. Found {found} matching files.")
