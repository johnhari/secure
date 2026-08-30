import os
import glob

pub_cache = os.path.expandvars(r'%USERPROFILE%\.pub-cache')
if not os.path.exists(pub_cache):
    pub_cache = os.path.expandvars(r'%LOCALAPPDATA%\Pub\Cache')

search_pattern = os.path.join(pub_cache, '**', 'syncfusion_flutter_charts-*')
folders = glob.glob(search_pattern, recursive=True)

for folder in folders:
    if '27.2.5' in folder:
        axis_files = glob.glob(os.path.join(folder, '**', 'category_axis.dart'), recursive=True)
        axis_files += glob.glob(os.path.join(folder, '**', 'axis.dart'), recursive=True)
        print(f"Found axis files: {axis_files}")
        for af in axis_files:
            print(f"Inspecting {af}:")
            with open(af, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            # print class definition and its constructor parameters
            lines = content.split('\n')
            in_constructor = False
            for line in lines:
                if 'class CategoryAxis' in line or 'class ChartAxis' in line:
                    print("  ", line.strip())
                if 'CategoryAxis(' in line or 'ChartAxis(' in line:
                    in_constructor = True
                if in_constructor:
                    print("    ", line.strip())
                    if ')' in line and ';' not in line:
                        in_constructor = False
