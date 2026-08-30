import zipfile
import os

zip_path = r"C:\Users\PUTIN\Desktop\ADVANCEORDERFLOW_backup_20260610_075757.zip"

if not os.path.exists(zip_path):
    print("Zip file not found")
    exit(1)

with zipfile.ZipFile(zip_path, 'r') as zip_ref:
    for name in zip_ref.namelist():
        if "chart_screen.dart" in name:
            print("Found in zip:", name)
            content = zip_ref.read(name).decode('utf-8', errors='ignore')
            lines = content.splitlines()
            print(f"Size: {len(content)} bytes, Lines: {len(lines)}")
            # print first 10 lines
            print("\nFirst 10 lines:")
            for l in lines[:10]:
                print(" ", l)
