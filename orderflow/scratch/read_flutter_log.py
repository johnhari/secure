path = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain\8e6dca80-a13f-4183-82de-5254a4fddb31\.system_generated\tasks\task-676.log"
with open(path, "r", encoding="utf-8", errors="ignore") as f:
    lines = f.readlines()

print("Last 100 lines of Flutter run task log (cleaned):")
for line in lines[-150:]:
    cleaned = line.encode("ascii", "replace").decode("ascii")
    print(cleaned.strip())
