import os

appdata_local = os.environ.get("LOCALAPPDATA", r"C:\Users\PUTIN\AppData\Local")
appdata_roaming = os.environ.get("APPDATA", r"C:\Users\PUTIN\AppData\Roaming")

print("Searching for Backups folders...")

for base_dir in [appdata_local, appdata_roaming]:
    for root, dirs, files in os.walk(base_dir):
        if any(p in root.lower() for p in ["cache", "npm", "pip", "temp"]):
            continue
        for d in dirs:
            if "backup" in d.lower():
                path = os.path.join(root, d)
                print(f"Found folder: {path}")
                # List files in this directory
                try:
                    for f in os.listdir(path):
                        f_path = os.path.join(path, f)
                        if os.path.isdir(f_path):
                            print(f"  Subfolder: {f}")
                        else:
                            print(f"  File: {f} | Size: {os.path.getsize(f_path)} bytes")
                except:
                    pass
print("Finished search.")
