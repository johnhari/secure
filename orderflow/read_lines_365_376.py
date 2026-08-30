import os
import json

path = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain\b04f87cf-d6de-4e4a-a77a-c0905c9dcc3f\.system_generated\logs\transcript.jsonl"

with open(path, "r", encoding="utf-8", errors="ignore") as f:
    for i, line in enumerate(f):
        if 365 <= i <= 376:
            try:
                data = json.loads(line)
                print(f"Line {i}, Step {data.get('step_index')}, Type: {data.get('type')}")
                if "tool_calls" in data:
                    for tc in data["tool_calls"]:
                        print("  Tool:", tc.get("name"))
                        args = tc.get("args") or tc.get("arguments") or {}
                        if isinstance(args, str):
                            args = json.loads(args)
                        print("  Args keys:", list(args.keys()))
                        print("  Desc:", args.get("Description"))
                        print("  Inst:", args.get("Instruction"))
                        if "TargetContent" in args:
                            print("  TargetContent (truncated):", repr(args.get("TargetContent"))[:200])
                        if "ReplacementContent" in args:
                            print("  ReplacementContent (truncated):", repr(args.get("ReplacementContent"))[:200])
                        if "ReplacementChunks" in args:
                            print("  Chunks count:", len(args.get("ReplacementChunks")))
            except Exception as e:
                print("Error parsing line:", e)
