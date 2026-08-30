import os

dart_tool_dir = r"C:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\.dart_tool"
term = "_AnimatedOrderflowCounter"

print("Searching .dart_tool directory for:", term)

if not os.path.exists(dart_tool_dir):
    print(".dart_tool directory does not exist")
    exit(1)

found = 0
for root, dirs, files in os.walk(dart_tool_dir):
    for f in files:
        path = os.path.join(root, f)
        try:
            # Skip huge binary files or read them carefully
            size = os.path.getsize(path)
            if size > 10 * 1024 * 1024: # 10MB
                continue
            with open(path, "r", encoding="utf-8", errors="ignore") as file:
                content = file.read()
            if term in content:
                print(f"Found in file: {path} | Size: {size} bytes")
                found += 1
        except Exception as e:
            pass

print(f"Search finished. Found {found} occurrences.")
