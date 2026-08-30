import os
import json

path = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain\b04f87cf-d6de-4e4a-a77a-c0905c9dcc3f\.system_generated\logs\transcript.jsonl"

with open(path, "r", encoding="utf-8", errors="ignore") as f:
    for i, line in enumerate(f):
        try:
            data = json.loads(line)
            step = data.get("step_index")
            if 130 <= step <= 145:
                print(f"\nLine {i}, Step {step}, Type: {data.get('type')}")
                tool_calls = data.get("tool_calls", [])
                for tc in tool_calls:
                    print("  Tool:", tc.get("name"))
                    args = tc.get("args") or tc.get("arguments") or {}
                    if isinstance(args, str):
                        args = json.loads(args)
                    print("  Description:", args.get("Description"))
                    print("  Instruction:", args.get("Instruction"))
                    if "TargetContent" in args:
                        print("  TargetContent length:", len(args.get("TargetContent")))
                    if "ReplacementContent" in args:
                        print("  ReplacementContent length:", len(args.get("ReplacementContent")))
                    if "ReplacementChunks" in args:
                        chunks = args.get("ReplacementChunks", [])
                        if isinstance(chunks, str):
                            chunks = json.loads(chunks)
                        print(f"  Chunks count: {len(chunks)}")
                        for idx, chunk in enumerate(chunks):
                            print(f"    Chunk {idx}: StartLine={chunk.get('StartLine')}, EndLine={chunk.get('EndLine')}")
                            print(f"      TargetContent length:", len(chunk.get("TargetContent", "")))
                            print(f"      ReplacementContent length:", len(chunk.get("ReplacementContent", "")))
        except:
            pass
