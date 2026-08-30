import os
import json

path = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain\b04f87cf-d6de-4e4a-a77a-c0905c9dcc3f\.system_generated\logs\transcript.jsonl"

print("Searching for 'footprint' in transcript b04f87cf before line 379...")

with open(path, "r", encoding="utf-8", errors="ignore") as f:
    for i, line in enumerate(f):
        if i >= 379:
            break
        if "footprint" in line.lower():
            try:
                data = json.loads(line)
                print(f"Line {i}, Step {data.get('step_index')}, Type: {data.get('type')}, Source: {data.get('source')}")
                tool_calls = data.get("tool_calls", [])
                for tc in tool_calls:
                    name = tc.get("name")
                    args = tc.get("args") or tc.get("arguments") or {}
                    if isinstance(args, str):
                        args = json.loads(args)
                    print(f"  Tool: {name} | TargetFile: {args.get('TargetFile') or args.get('AbsolutePath')}")
                    # Print description/instruction
                    print("  Desc:", args.get("Description"))
                    print("  Inst:", args.get("Instruction"))
            except Exception as e:
                pass
print("Done.")
