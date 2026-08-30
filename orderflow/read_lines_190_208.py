import os
import json

path = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain\b04f87cf-d6de-4e4a-a77a-c0905c9dcc3f\.system_generated\logs\transcript.jsonl"

with open(path, "r", encoding="utf-8", errors="ignore") as f:
    for i, line in enumerate(f):
        if 190 <= i <= 208:
            try:
                data = json.loads(line)
                print(f"\nLine {i}, Step {data.get('step_index')}, Type: {data.get('type')}")
                tool_calls = data.get("tool_calls", [])
                for tc in tool_calls:
                    print("  Tool:", tc.get("name"))
                    args = tc.get("args") or tc.get("arguments") or {}
                    if isinstance(args, str):
                        args = json.loads(args)
                    print("  Args keys:", list(args.keys()))
                    print("  Description:", args.get("Description"))
                    print("  Instruction:", args.get("Instruction"))
                    if "TargetContent" in args:
                        print("  TargetContent (truncated):", repr(args.get("TargetContent"))[:200])
                    if "ReplacementContent" in args:
                        print("  ReplacementContent (truncated):", repr(args.get("ReplacementContent"))[:200])
                    if "ReplacementChunks" in args:
                        chunks = args.get("ReplacementChunks", [])
                        if isinstance(chunks, str):
                            chunks = json.loads(chunks)
                        print(f"  Chunks count: {len(chunks)}")
                        for idx, chunk in enumerate(chunks):
                            print(f"    Chunk {idx}: StartLine={chunk.get('StartLine')}, EndLine={chunk.get('EndLine')}")
                            print(f"      TargetContent (truncated):", repr(chunk.get("TargetContent"))[:150])
                            print(f"      ReplacementContent (truncated):", repr(chunk.get("ReplacementContent"))[:150])
            except Exception as e:
                print("Error parsing line:", e)
