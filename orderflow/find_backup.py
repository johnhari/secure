import os
import json

brain_dir = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain"
transcripts = []
for root, dirs, files in os.walk(brain_dir):
    for f in files:
        if f == "transcript.jsonl":
            path = os.path.join(root, f)
            transcripts.append(path)

for path in transcripts:
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for i, line in enumerate(f):
            if "git restore" in line.lower():
                print(f"Found git restore in {path} at line {i}:")
                try:
                    data = json.loads(line)
                    print(f"  Step {data.get('step_index')}, Type: {data.get('type')}, Source: {data.get('source')}")
                    if "tool_calls" in data:
                        for tc in data["tool_calls"]:
                            print(f"    Tool: {tc.get('name')}, Args: {tc.get('arguments')}")
                    if "content" in data:
                        print(f"    Content snippet: {data['content'][:300]}")
                except Exception as e:
                    print(f"    Raw snippet: {line[:300]}")
