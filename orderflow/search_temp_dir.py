import os

temp_dir = os.environ.get("TEMP", r"C:\Users\PUTIN\AppData\Local\Temp")
print("Scanning temp directory:", temp_dir)

if not os.path.exists(temp_dir):
    print("Temp directory does not exist")
    exit(1)

search_terms = ["_AnimatedOrderflowCounter", "_buildSpecialEffectLayers"]
found = 0

for root, dirs, files in os.walk(temp_dir):
    # Skip directories with many tiny files to avoid slow scans
    if any(p in root.lower() for p in ["npm", "cache", "package"]):
        continue
    for f in files:
        path = os.path.join(root, f)
        try:
            size = os.path.getsize(path)
            # Skip massive files
            if size > 5 * 1024 * 1024:
                continue
            with open(path, "r", encoding="utf-8", errors="ignore") as file:
                content = file.read()
            for term in search_terms:
                if term in content:
                    print(f"Found '{term}' in temp file: {path} | Size: {size} bytes")
                    
                    # Save a copy
                    out_path = f"C:\\Users\\PUTIN\\Desktop\\ADVANCEORDERFLOW\\orderflow\\recovered_temp_{f}_{size}.dart"
                    with open(out_path, "w", encoding="utf-8") as out_f:
                        out_f.write(content)
                    print(f"  Saved copy to: {out_path}")
                    found += 1
        except:
            pass

print(f"Search finished. Found {found} matching files.")
