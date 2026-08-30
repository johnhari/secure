import os
import json

path = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain\b04f87cf-d6de-4e4a-a77a-c0905c9dcc3f\.system_generated\logs\transcript.jsonl"

print("Inspecting tool calls targeting chart_screen.dart...")

with open(path, "r", encoding="utf-8", errors="ignore") as f:
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
                    
                    target_file = args.get("TargetFile") or args.get("AbsolutePath") or ""
                    if "chart_screen.dart" in target_file:
                        if name in ["replace_file_content", "multi_replace_file_content", "write_to_file"]:
                            print(f"\n--- Line {i}, Step {data.get('step_index')}, Tool: {name} ---")
                            print("Description:", args.get("Description"))
                            print("Instruction:", args.get("Instruction"))
                            if name == "replace_file_content":
                                print("StartLine:", args.get("StartLine"), "EndLine:", args.get("EndLine"))
                                print("TargetContent (truncated):", repr(args.get("TargetContent"))[:200])
                                print("ReplacementContent (truncated):", repr(args.get("ReplacementContent"))[:200])
                            elif name == "multi_replace_file_content":
                                chunks = args.get("ReplacementChunks", [])
                                print(f"Chunks count: {len(chunks)}")
                                for idx, chunk in enumerate(chunks):
                                    print(f"  Chunk {idx}: StartLine={chunk.get('StartLine')}, EndLine={chunk.get('EndLine')}")
                                    print(f"    TargetContent (truncated):", repr(chunk.get("TargetContent"))[:150])
                                    print(f"    ReplacementContent (truncated):", repr(chunk.get("ReplacementContent"))[:150])
            except Exception as e:
                pass
print("\nDone inspecting.")
