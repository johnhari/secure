import os

root_dir = r"C:\Users\PUTIN\.gemini\antigravity-ide"
print("Scanning .gemini folder for any .dart files...")

found = 0
for root, dirs, files in os.walk(root_dir):
    # skip log file directory to be fast
    if ".system_generated" in root:
        continue
    for f in files:
        if f.endswith(".dart"):
            path = os.path.join(root, f)
            print(f"Found file: {path} | Size: {os.path.getsize(path)} bytes")
            found += 1

print(f"Done. Found {found} files.")
