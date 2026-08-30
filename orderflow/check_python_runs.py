import os
import json

path = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain\b04f87cf-d6de-4e4a-a77a-c0905c9dcc3f\.system_generated\logs\transcript.jsonl"

with open(path, "r", encoding="utf-8", errors="ignore") as f:
    for i, line in enumerate(f):
        if "python" in line.lower() or "repair_layout" in line.lower():
            try:
                data = json.loads(line)
                if "tool_calls" in data:
                    for tc in data["tool_calls"]:
                        print(f"Line {i}, Step {data.get('step_index')}, Tool: {tc.get('name')}, Args: {json.dumps(tc.get('args'))}")
                elif "type" in data and data["type"] == "RUN_COMMAND":
                    print(f"Line {i}, Completed CMD Step {data.get('step_index')}, Content snippet: {data.get('content')[:300]}")
            except:
                pass
