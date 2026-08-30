import json
import os

path = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain\b04f87cf-d6de-4e4a-a77a-c0905c9dcc3f\.system_generated\logs\transcript.jsonl"

with open(path, "r", encoding="utf-8", errors="ignore") as f:
    for i, line in enumerate(f):
        if '"step_index":126' in line:
            try:
                data = json.loads(line)
                print("Step 126 found at line", i)
                tool_calls = data.get("tool_calls", [])
                for tc in tool_calls:
                    args = tc.get("args") or tc.get("arguments") or {}
                    if isinstance(args, str):
                        args = json.loads(args)
                    raw_chunks = args.get("ReplacementChunks")
                    print("Type of ReplacementChunks:", type(raw_chunks))
                    if isinstance(raw_chunks, str):
                        print("Length:", len(raw_chunks))
                        print("Prefix:", repr(raw_chunks[:200]))
                        # Let's try parsing it after replacing control chars
                        try:
                            chunks = json.loads(raw_chunks)
                            print("Success parsing directly!")
                        except Exception as e:
                            print("Direct parse error:", e)
                            # Let's inspect the error location
                            err_idx = int(str(e).split("char ")[1].rstrip(")"))
                            print("Error location character:", repr(raw_chunks[err_idx-20:err_idx+20]))
            except Exception as e:
                print("Error loading line:", e)
            break
