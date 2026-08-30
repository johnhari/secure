import os
import datetime

brain_dir = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain"
print("Scanning brain directory for markdown artifacts...")

if not os.path.exists(brain_dir):
    print("Brain directory does not exist")
    exit(1)

for root, dirs, files in os.walk(brain_dir):
    for f in files:
        if f in ["walkthrough.md", "implementation_plan.md"]:
            path = os.path.join(root, f)
            mtime = os.path.getmtime(path)
            dt = datetime.datetime.fromtimestamp(mtime)
            print(f"\n======================================")
            print(f"Artifact: {path} | Size: {os.path.getsize(path)} bytes | Modified: {dt}")
            print(f"======================================")
            try:
                with open(path, "r", encoding="utf-8", errors="ignore") as file:
                    content = file.read()
                print(content[:800])
                if len(content) > 800:
                    print("... [TRUNCATED] ...")
            except Exception as e:
                print("Error reading:", e)
