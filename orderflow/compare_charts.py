import os

jio_path = r"C:\Users\PUTIN\Desktop\JIO\JC-Jeevanan-610d\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\chart_screen.dart"
cur_path = r"C:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\chart_screen.dart"

def find_def(path, name):
    if not os.path.exists(path):
        return "not found"
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()
    if name in content:
        # Find line number and definition
        lines = content.splitlines()
        for idx, line in enumerate(lines):
            if f"class {name}" in line or f"class _{name}" in line or f"widget {name}" in line or f"void _{name}" in line:
                return f"Line {idx+1}: {line.strip()}"
        return "exists but class/method def not found in simple search"
    return "not found"

print("JIO _AnimatedOrderflowCounter:", find_def(jio_path, "AnimatedOrderflowCounter"))
print("Current _AnimatedOrderflowCounter:", find_def(cur_path, "AnimatedOrderflowCounter"))
print("JIO _buildSpecialEffectLayers:", find_def(jio_path, "buildSpecialEffectLayers"))
print("Current _buildSpecialEffectLayers:", find_def(cur_path, "buildSpecialEffectLayers"))
