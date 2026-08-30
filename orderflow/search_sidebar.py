import os
import json

path = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain\b04f87cf-d6de-4e4a-a77a-c0905c9dcc3f\.system_generated\logs\transcript.jsonl"

print("Searching for _buildFootprintSidebar in logs...")

with open(path, "r", encoding="utf-8", errors="ignore") as f:
    for i, line in enumerate(f):
        if "_buildFootprintSidebar" in line:
            try:
                data = json.loads(line)
                print(f"Line {i}, Step {data.get('step_index')}, Type: {data.get('type')}")
                tool_calls = data.get("tool_calls", [])
                for tc in tool_calls:
                    name = tc.get("name")
                    args = tc.get("args") or tc.get("arguments") or {}
                    if isinstance(args, str):
                        args = json.loads(args)
                    print(f"  Tool: {name} | TargetFile: {args.get('TargetFile')}")
                    # Print snippet of chunk
                    if name == "replace_file_content":
                        print("  TargetContent (truncated):", repr(args.get("TargetContent"))[:200])
                        print("  ReplacementContent (truncated):", repr(args.get("ReplacementContent"))[:200])
                    elif name == "multi_replace_file_content":
                        chunks = args.get("ReplacementChunks", [])
                        print("  Chunks count:", len(chunks))
            except Exception as e:
                pass
print("Done.")
