import os
import json

path = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain\b04f87cf-d6de-4e4a-a77a-c0905c9dcc3f\.system_generated\logs\transcript.jsonl"

with open(path, "r", encoding="utf-8", errors="ignore") as f:
    for i, line in enumerate(f):
        if 375 <= i <= 385:
            try:
                data = json.loads(line)
                print(f"Line {i}, Step {data.get('step_index')}, Type: {data.get('type')}")
                if "content" in data:
                    print("Content prefix:", data["content"][:400])
                if "tool_calls" in data:
                    for tc in data["tool_calls"]:
                        print("  Tool:", tc.get("name"), "Args:", json.dumps(tc.get("args"))[:200])
            except Exception as e:
                print("Error parsing line:", e)
