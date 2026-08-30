import os

file_path = r'C:\Users\PUTIN\AppData\Local\Pub\Cache\hosted\pub.dev\syncfusion_flutter_charts-27.2.5\lib\src\charts\behaviors\zooming.dart'

if os.path.exists(file_path):
    print("Reading zooming.dart around zoomToSingleAxis:")
    with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()
    
    for idx, line in enumerate(lines):
        if 'zoomToSingleAxis' in line:
            # print 20 lines before and after
            for i in range(max(0, idx - 5), min(len(lines), idx + 25)):
                print(f"{i+1}: {lines[i].strip()}")
            break
