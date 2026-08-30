import json
import os

log_path = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain\b04f87cf-d6de-4e4a-a77a-c0905c9dcc3f\.system_generated\logs\transcript.jsonl"
out_dir = r"C:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\extracted_edits"

os.makedirs(out_dir, exist_ok=True)

with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
    for i, line in enumerate(f):
        if "chart_screen.dart" in line:
            try:
                data = json.loads(line)
                step_idx = data.get("step_index")
                tool_calls = data.get("tool_calls", [])
                
                for tc_idx, tc in enumerate(tool_calls):
                    name = tc.get("name")
                    args = tc.get("args") or tc.get("arguments") or {}
                    if isinstance(args, str):
                        args = json.loads(args)
                    
                    target_file = args.get("TargetFile") or ""
                    if "chart_screen.dart" in target_file:
                        out_file = os.path.join(out_dir, f"step_{step_idx}_{name}_{tc_idx}.json")
                        with open(out_file, "w", encoding="utf-8") as out_f:
                            json.dump(args, out_f, indent=2)
                        print(f"Extracted step {step_idx} ({name}) to {out_file}")
            except Exception as e:
                pass
print("Extraction complete.")
