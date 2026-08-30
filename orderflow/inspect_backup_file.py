import os

path = r"C:\Users\PUTIN\AppData\Roaming\Antigravity IDE\Backups\a2210aee80f4d15ca7aa3d95abda0dc7\file\2e0b30f3"

print("Inspecting backup file:", path)
if not os.path.exists(path):
    print("File not found")
    exit(1)

size = os.path.getsize(path)
print(f"Size: {size} bytes")

with open(path, "r", encoding="utf-8", errors="ignore") as f:
    content = f.read()

print("Length of read content:", len(content))

# Search for mentions of file paths or class names
search_terms = ["chart_screen.dart", "class ChartScreen", "_AnimatedOrderflowCounter"]
for term in search_terms:
    if term in content:
        print(f"Found term '{term}' at index:", content.find(term))
        # Print context around it
        idx = content.find(term)
        print("Context:")
        print(content[max(0, idx-200):min(len(content), idx+500)])
        print("--------------------\n")
    else:
        print(f"Term '{term}' not found.")
