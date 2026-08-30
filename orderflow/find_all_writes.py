import os
import json

path = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain\b04f87cf-d6de-4e4a-a77a-c0905c9dcc3f\.system_generated\logs\transcript.jsonl"

with open(path, "r", encoding="utf-8", errors="ignore") as f:
    for i, line in enumerate(f):
        if "write_to_file" in line:
            try:
                data = json.loads(line)
                tool_calls = data.get("tool_calls", [])
                for tc in tool_calls:
                    if tc.get("name") == "write_to_file":
                        args = tc.get("args") or tc.get("arguments") or {}
                        if isinstance(args, str):
                            args = json.loads(args)
                        print(f"Line {i}, Step {data.get('step_index')}: TargetFile={args.get('TargetFile')}, CodeContent Length={len(args.get('CodeContent', ''))}")
            except Exception as e:
                pass
