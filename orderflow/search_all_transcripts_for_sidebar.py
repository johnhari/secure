import os
import json

brain_dir = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain"
print("Scanning all transcripts for _buildFootprintSidebar...")

transcripts = []
for root, dirs, files in os.walk(brain_dir):
    for f in files:
        if f == "transcript.jsonl":
            transcripts.append(os.path.join(root, f))

found = 0
for path in transcripts:
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for i, line in enumerate(f):
            if "_buildFootprintSidebar" in line:
                # get session id from path
                session_id = os.path.basename(os.path.dirname(os.path.dirname(path)))
                print(f"Found in session {session_id} at line {i}:")
                try:
                    data = json.loads(line)
                    print(f"  Step {data.get('step_index')}, Type: {data.get('type')}, Source: {data.get('source')}")
                    if "tool_calls" in data:
                        for tc in data["tool_calls"]:
                            print(f"    Tool: {tc.get('name')}")
                            args = tc.get("args") or tc.get("arguments") or {}
                            if isinstance(args, str):
                                args = json.loads(args)
                            print(f"    Description: {args.get('Description')}")
                            print(f"    Instruction: {args.get('Instruction')}")
                            # check if it contains the full definition
                            rep = args.get("ReplacementContent", "") or args.get("CodeContent", "")
                            if "_buildFootprintSidebar" in rep:
                                print(f"    [!] Contains full definition! Length: {len(rep)} bytes")
                                # Save it
                                out_path = f"C:\\Users\\PUTIN\\Desktop\\ADVANCEORDERFLOW\\orderflow\\extracted_edits\\recovered_def_{session_id}_{i}.dart"
                                with open(out_path, "w", encoding="utf-8") as out_f:
                                    out_f.write(rep)
                                print(f"    Saved definition to: {out_path}")
                                found += 1
                except Exception as e:
                    print("    Error:", e)

print(f"Search finished. Found {found} occurrences with definitions.")
