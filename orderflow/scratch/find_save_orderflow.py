with open(r'c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\chart_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

found_idx = -1
for idx, line in enumerate(lines):
    if 'void _saveOrderflow' in line or 'Future<void> _saveOrderflow' in line:
        found_idx = idx
        print(f"Found _saveOrderflow starting at line {idx+1}")
        break

if found_idx != -1:
    # print 120 lines from found_idx
    for i in range(found_idx, min(len(lines), found_idx + 120)):
        print(f"{i+1}: {lines[i].rstrip()}")
