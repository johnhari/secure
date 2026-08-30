import json
import os

log_path = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain\b04f87cf-d6de-4e4a-a77a-c0905c9dcc3f\.system_generated\logs\transcript.jsonl"

steps_to_inspect = []

with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
    for i, line in enumerate(f):
        if "chart_screen.dart" in line:
            try:
                data = json.loads(line)
                tool_calls = data.get("tool_calls", [])
                for tc in tool_calls:
                    name = tc.get("name")
                    args = tc.get("args") or tc.get("arguments") or {}
                    if isinstance(args, str):
                        args = json.loads(args)
                    
                    target_file = args.get("TargetFile") or ""
                    if "chart_screen.dart" in target_file:
                        if name in ["replace_file_content", "multi_replace_file_content"]:
                            steps_to_inspect.append({
                                "step_index": data.get("step_index"),
                                "line_num": i,
                                "tool": name,
                                "args": args
                            })
            except:
                pass

print(f"Found {len(steps_to_inspect)} total edits to check.")

for edit in steps_to_inspect:
    step = edit["step_index"]
    tool = edit["tool"]
    args = edit["args"]
    desc = args.get("Description", "")
    
    # Check if this edit has truncation
    args_str = json.dumps(args)
    is_truncated = "truncated" in args_str.lower()
    
    print(f"Step {step} | Tool: {tool} | Truncated: {is_truncated} | Desc: {desc[:80]}...")
