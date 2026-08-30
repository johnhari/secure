import os
import json

path = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain\905d286f-4a8d-46d6-9f22-13aa77bcfca3\.system_generated\logs\transcript.jsonl"

with open(path, "r", encoding="utf-8", errors="ignore") as f:
    for i, line in enumerate(f):
        if "task-144" in line:
            try:
                data = json.loads(line)
                print(f"Line {i}, Step {data.get('step_index')}, Type: {data.get('type')}")
                if "content" in data:
                    print("Content:", data["content"][:600])
            except Exception as e:
                pass
