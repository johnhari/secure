import json
import os

log_path = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain\b04f87cf-d6de-4e4a-a77a-c0905c9dcc3f\.system_generated\logs\transcript.jsonl"
chart_path = r"C:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\chart_screen.dart"

# First, let's restore chart_screen.dart to the clean initial commit state using git
print("Running git checkout to ensure clean starting file...")
os.system("git checkout orderflow/lib/presentation/screens/chart_screen.dart")

with open(chart_path, "r", encoding="utf-8") as f:
    current_code = f.read()

print(f"Loaded starting chart_screen.dart: {len(current_code)} bytes, {len(current_code.splitlines())} lines.")

steps_edits = []

with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
    for i, line in enumerate(f):
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
                        steps_edits.append({
                            "step_index": data.get("step_index"),
                            "line_num": i,
                            "tool": name,
                            "args": args
                        })
        except Exception as e:
            pass

# Sort edits by step_index
steps_edits.sort(key=lambda x: x["step_index"])
print(f"Found {len(steps_edits)} edits to apply.")

applied_count = 0
failed_count = 0

for edit in steps_edits:
    step = edit["step_index"]
    tool = edit["tool"]
    args = edit["args"]
    desc = args.get("Description", "")
    
    print(f"\n--- Applying Edit Step {step} ({tool}) ---")
    print(f"Description: {desc}")
    
    chunks = []
    if tool == "replace_file_content":
        chunks.append({
            "target": args.get("TargetContent"),
            "replacement": args.get("ReplacementContent")
        })
    elif tool == "multi_replace_file_content":
        raw_chunks = args.get("ReplacementChunks", [])
        if isinstance(raw_chunks, str):
            try:
                raw_chunks = json.loads(raw_chunks)
            except Exception as e:
                print(f"  Error parsing chunks string: {e}")
                raw_chunks = []
        for chunk in raw_chunks:
            if isinstance(chunk, dict):
                chunks.append({
                    "target": chunk.get("TargetContent"),
                    "replacement": chunk.get("ReplacementContent")
                })
    
    for idx, chunk in enumerate(chunks):
        target = chunk["target"]
        replacement = chunk["replacement"]
        
        if not target:
            print(f"  Chunk {idx}: Target is empty!")
            continue
            
        if target in current_code:
            current_code = current_code.replace(target, replacement)
            print(f"  Chunk {idx}: Replaced successfully. Target length: {len(target)}, Replacement length: {len(replacement)}")
            applied_count += 1
        else:
            # Let's try cleaning up potential trailing whitespace or windows line endings differences
            target_clean = target.replace("\r\n", "\n").strip()
            # Try finding normalized matches
            norm_code = current_code.replace("\r\n", "\n")
            if target_clean in norm_code:
                norm_code = norm_code.replace(target_clean, replacement.replace("\r\n", "\n"))
                current_code = norm_code
                print(f"  Chunk {idx}: Replaced successfully using normalized line endings.")
                applied_count += 1
            else:
                print(f"  Chunk {idx}: FAILED to find target content.")
                print("  Target content start:", repr(target[:150]))
                failed_count += 1

print(f"\nReconstruction complete. Applied: {applied_count}, Failed: {failed_count}")
print(f"Final code size: {len(current_code)} bytes, {len(current_code.splitlines())} lines.")

# Write it back to chart_screen.dart
with open(chart_path, "w", encoding="utf-8") as f:
    f.write(current_code)
print("Saved final code to chart_screen.dart.")
