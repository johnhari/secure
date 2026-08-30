import os

file_path = r'C:\Users\PUTIN\AppData\Local\Pub\Cache\hosted\pub.dev\syncfusion_flutter_charts-27.2.5\lib\src\charts\axis\axis.dart'

if os.path.exists(file_path):
    print("Reading axis.dart:")
    with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()
    
    in_class = False
    class_indent = 0
    for idx, line in enumerate(lines):
        if 'class ChartAxisController' in line or 'class CategoryAxisController' in line:
            print(f"\n--- Found Class definition: {line.strip()} at line {idx+1} ---")
            # print next 30 lines
            for i in range(idx, min(len(lines), idx + 40)):
                print(f"{i+1}: {lines[i].rstrip()}")
else:
    print(f"File not found: {file_path}")
