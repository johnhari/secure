import os
import json

path = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain\905d286f-4a8d-46d6-9f22-13aa77bcfca3\.system_generated\logs\transcript.jsonl"

with open(path, "r", encoding="utf-8", errors="ignore") as f:
    for i, line in enumerate(f):
        if i == 174:
            try:
                data = json.loads(line)
                print("Thinking of Step 108:")
                print(data.get("thinking"))
            except Exception as e:
                print("Error:", e)
