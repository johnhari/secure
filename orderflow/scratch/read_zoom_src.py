import os

file_path = r'C:\Users\PUTIN\AppData\Local\Pub\Cache\hosted\pub.dev\syncfusion_flutter_charts-27.2.5\lib\src\charts\behaviors\zooming.dart'

if os.path.exists(file_path):
    print("Reading zooming.dart:")
    with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()
    
    in_class = False
    for line in lines:
        if 'class ZoomPanBehavior' in line:
            in_class = True
        if in_class:
            if 'void ' in line or 'double ' in line or 'ZoomPanBehavior(' in line:
                if not line.strip().startswith('//') and not line.strip().startswith('*'):
                    print(line.strip())
            # stop if we reach the end of the class
            if in_class and line.startswith('}'):
                # just print a bit of it
                pass
else:
    print(f"File not found: {file_path}")
