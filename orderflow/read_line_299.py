import os
import json

path = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain\b04f87cf-d6de-4e4a-a77a-c0905c9dcc3f\.system_generated\logs\transcript.jsonl"

with open(path, "r", encoding="utf-8", errors="ignore") as f:
    for i, line in enumerate(f):
        if i == 299:
            try:
                data = json.loads(line)
                print("Line 299 Step Index:", data.get("step_index"))
                print("Type:", data.get("type"))
                tool_calls = data.get("tool_calls", [])
                for tc in tool_calls:
                    print("  Tool:", tc.get("name"))
                    args = tc.get("args") or tc.get("arguments") or {}
                    if isinstance(args, str):
                        args = json.loads(args)
                    print("  TargetFile:", args.get("TargetFile"))
                    code = args.get("CodeContent", "")
                    print("  CodeContent Length:", len(code))
                    if len(code) > 0:
                        print("  CodeContent starts with:")
                        print(code[:200])
                        print("  CodeContent ends with:")
                        print(code[-200:])
            except Exception as e:
                print("Error parsing Line 299:", e)
            break
