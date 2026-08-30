import os
import json

path = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain\905d286f-4a8d-46d6-9f22-13aa77bcfca3\.system_generated\logs\transcript.jsonl"

with open(path, "r", encoding="utf-8", errors="ignore") as f:
    for i, line in enumerate(f):
        if 160 <= i <= 180:
            try:
                data = json.loads(line)
                if "tool_calls" in data:
                    for tc in data["tool_calls"]:
                        print(f"Step {data.get('step_index')}, Tool: {tc.get('name')}, Args: {json.dumps(tc.get('arguments'))}")
                elif "type" in data and data["type"] == "RUN_COMMAND":
                    # For completed run_commands, let's see their content/output
                    print(f"Completed CMD Step {data.get('step_index')}, Content snippet: {data.get('content')[:200]}")
            except Exception as e:
                pass
