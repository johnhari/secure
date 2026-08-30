import os
import zipfile

desktop_dir = r"C:\Users\PUTIN\Desktop"
search_terms = ["_AnimatedOrderflowCounter", "_buildSpecialEffectLayers", "Dynamic Orderflow Animation"]

print("Searching Desktop for lost orderflow code...")

for root, dirs, files in os.walk(desktop_dir):
    if any(p in root.lower() for p in ["node_modules", "build", ".git", ".dart_tool"]):
        continue
    for f in files:
        path = os.path.join(root, f)
        # Check text files
        if f.endswith(".dart") or f.endswith(".py") or f.endswith(".txt") or f.endswith(".md"):
            try:
                with open(path, "r", encoding="utf-8", errors="ignore") as file:
                    content = file.read()
                for term in search_terms:
                    if term in content:
                        print(f"Found '{term}' in file: {path} | Size: {os.path.getsize(path)} bytes")
            except Exception as e:
                pass
        
        # Check zip files
        elif f.endswith(".zip"):
            try:
                with zipfile.ZipFile(path, 'r') as zip_ref:
                    for name in zip_ref.namelist():
                        if name.endswith((".dart", ".py", ".txt", ".md")):
                            try:
                                zip_content = zip_ref.read(name).decode('utf-8', errors='ignore')
                                for term in search_terms:
                                    if term in zip_content:
                                        print(f"Found '{term}' inside zip '{f}': {name}")
                            except:
                                pass
            except Exception as e:
                pass
print("Search finished.")
