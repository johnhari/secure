import os
import zipfile

root_dir = r"C:\Users\PUTIN\Desktop\ADVANCEORDERFLOW"
term = "_AnimatedOrderflowCounter"

print("Searching entire workspace for:", term)

found = 0
for root, dirs, files in os.walk(root_dir):
    if ".git" in root:
        continue
    for f in files:
        path = os.path.join(root, f)
        
        # Check standard files
        if f.endswith((".dart", ".py", ".txt", ".md", ".json", ".bin", ".dill", ".so")):
            try:
                size = os.path.getsize(path)
                if size > 15 * 1024 * 1024: # 15MB
                    continue
                with open(path, "r", encoding="utf-8", errors="ignore") as file:
                    content = file.read()
                if term in content:
                    print(f"Found in file: {path} | Size: {size} bytes")
                    found += 1
            except:
                pass
        
        # Check zip/apk files
        elif f.endswith((".zip", ".apk")):
            try:
                with zipfile.ZipFile(path, 'r') as zip_ref:
                    for name in zip_ref.namelist():
                        try:
                            zip_content = zip_ref.read(name).decode('utf-8', errors='ignore')
                            if term in zip_content:
                                print(f"Found inside archive '{f}': {name}")
                                found += 1
                        except:
                            pass
            except:
                pass

print(f"Search finished. Found {found} occurrences.")
