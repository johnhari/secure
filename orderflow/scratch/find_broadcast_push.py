with open(r'c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\chart_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

for idx, line in enumerate(lines):
    if 'saveOrderflowBulk' in line or 'broadcastPush' in line or 'broadcast' in line:
        print(f"Line {idx+1}: {line.strip()}")
