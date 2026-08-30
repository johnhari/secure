import os
import json

path = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain\b04f87cf-d6de-4e4a-a77a-c0905c9dcc3f\.system_generated\logs\transcript.jsonl"

print("Searching transcript for chart_screen.dart contents...")
with open(path, "r", encoding="utf-8", errors="ignore") as f:
    for i, line in enumerate(f):
        if "chart_screen.dart" in line:
            try:
                data = json.loads(line)
                # Check if this is a view_file response containing file content
                if data.get("type") == "VIEW_FILE":
                    content = data.get("content", "")
                    if "Total Lines: 76" in content or "Total Lines: 75" in content:
                        print(f"Line {i}: Found VIEW_FILE with large line count!")
                        print("Content prefix:", content[:300])
                        # Write the full content to a file to inspect it
                        out_path = f"C:\\Users\\PUTIN\\Desktop\\ADVANCEORDERFLOW\\orderflow\\recovered_chart_screen_{i}.dart"
                        with open(out_path, "w", encoding="utf-8") as out_f:
                            out_f.write(content)
                        print(f"Saved to {out_path}")
                
                # Check for write_to_file calls
                tool_calls = data.get("tool_calls", [])
                for tc in tool_calls:
                    if tc.get("name") == "write_to_file":
                        args = tc.get("arguments", {})
                        if isinstance(args, str):
                            args = json.loads(args)
                        if "chart_screen.dart" in args.get("TargetFile", ""):
                            print(f"Line {i}: Found write_to_file targeting chart_screen.dart!")
                            code = args.get("CodeContent", "")
                            out_path = f"C:\\Users\\PUTIN\\Desktop\\ADVANCEORDERFLOW\\orderflow\\recovered_write_{i}.dart"
                            with open(out_path, "w", encoding="utf-8") as out_f:
                                out_f.write(code)
                            print(f"Saved to {out_path}")
            except Exception as e:
                pass
print("Done searching.")
