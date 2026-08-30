import json
import os

log_file = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain\905d286f-4a8d-46d6-9f22-13aa77bcfca3\.system_generated\logs\transcript.jsonl"

with open(log_file, "r", encoding="utf-8") as f:
    for i, line in enumerate(f):
        try:
            data = json.loads(line)
            tool_calls = data.get("tool_calls", [])
            for tc in tool_calls:
                name = tc.get("name")
                args = tc.get("arguments", {})
                args_str = json.dumps(args)
                if "chart_screen.dart" in args_str or "git" in args_str:
                    print(f"Line {i}, Step {data.get('step_index')}, Type: {data.get('type')}, Tool: {name}")
                    print("  Arguments keys:", list(args.keys()) if isinstance(args, dict) else type(args))
                    # print some content
                    if "CommandLine" in args:
                        print("  CMD:", args["CommandLine"])
                    if "TargetContent" in args:
                        print("  TargetContent length:", len(args["TargetContent"]))
                    if "ReplacementContent" in args:
                        print("  ReplacementContent length:", len(args["ReplacementContent"]))
                    if "CodeContent" in args:
                        print("  CodeContent length:", len(args["CodeContent"]))
        except Exception as e:
            print(f"Error parsing line {i}: {e}")
