import os

jio_path = r"C:\Users\PUTIN\Desktop\JIO\JC-Jeevanan-610d\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\chart_screen.dart"

if not os.path.exists(jio_path):
    print("JIO file not found")
    exit(1)

with open(jio_path, "r", encoding="utf-8", errors="ignore") as f:
    code = f.read()

lines = code.splitlines()

# Search for classes and methods
def print_section(start_term, end_term_or_blank_line=True):
    for i, line in enumerate(lines):
        if start_term in line:
            print(f"--- Found '{start_term}' at line {i+1} ---")
            # print until next class/widget definition or matching brace
            j = i
            brace_count = 0
            started = False
            while j < len(lines):
                print(lines[j])
                # Track braces to find end of class/method
                brace_count += lines[j].count("{") - lines[j].count("}")
                if "{" in lines[j]:
                    started = True
                if started and brace_count == 0:
                    break
                j += 1
            print("------------------------------------------\n")

print_section("class _AnimatedOrderflowCounter")
print_section("List<Widget> _buildSpecialEffectLayers")
print_section("Widget _buildMicroParticle")
